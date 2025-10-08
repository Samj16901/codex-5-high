# Dokploy installation script for Windows with WSL2
#
# This script provisions Dokploy inside a WSL2 distribution and exposes its
# ports on the Windows host.  It is intended for Windows Server 2022 or
# Windows 11 systems with WSL2 enabled.  Run this script as an administrator.

param(
    [switch]$Update,
    [switch]$Rebind,
    [string]$Distro = "Ubuntu-22.04",
    [int]$HttpPort = 80,
    [int]$HttpsPort = 443,
    [string[]]$RouterHosts = @("dokploy.local"),
    [switch]$EnableTls,
    [string]$AcmeEmail,
    [string]$AcmeDnsProvider
)

function Get-WslIp {
    # Determine the IPv4 address of eth0 inside the WSL distribution.
    $ip = wsl -d $Distro -e sh -lc "ip -4 addr show eth0 | awk '/inet /{print \\\$2}' | cut -d/ -f1" 2>$null
    return $ip.Trim()
}

function Invoke-WslRootCommand {
    param([string]$Command)
    wsl -d $Distro -u root -e sh -lc $Command
}

function Invoke-WslRootCommandChecked {
    param([string]$Command)
    $result = Invoke-WslRootCommand $Command
    $exitCode = $LASTEXITCODE
    if ($exitCode -ne 0) {
        throw "WSL command failed ($Command) with exit code $exitCode"
    }
    return $result
}

function New-RandomPassword {
    param([int]$Length = 32)
    $chars = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789'
    -join ((1..$Length) | ForEach-Object { $chars[(Get-Random -Maximum $chars.Length)] })
}

function Test-PortFree {
    param([int]$Port)
    $connection = Get-NetTCPConnection -LocalPort $Port -ErrorAction SilentlyContinue
    if ($connection) {
        $portproxyConfig = netsh interface portproxy show v4tov4 2>$null
        $isPortProxy = $false
        if ($portproxyConfig) {
            $pattern = "\s+0\.0\.0\.0\s+$Port\s+"
            $isPortProxy = [bool]([regex]::Match($portproxyConfig, $pattern).Success)
        }
        if (-not $isPortProxy) {
            throw "Windows port $Port is in use"
        }
    }
}

function Configure-PortProxy {
    param([int[]]$Ports)
    $wslIp = Get-WslIp
    foreach ($p in $Ports) {
        netsh interface portproxy delete v4tov4 listenport=$p protocol=tcp 2>$null | Out-Null
        netsh interface portproxy add v4tov4 listenaddress=0.0.0.0 listenport=$p connectaddress=$wslIp connectport=$p protocol=tcp | Out-Null
        New-NetFirewallRule -DisplayName "Dokploy-$p" -Direction Inbound -Action Allow -Protocol TCP -LocalPort $p -ErrorAction SilentlyContinue | Out-Null
    }
}

function Ensure-TraefikConfig {
    param([switch]$TlsEnabled)
    $traefikDir = "/etc/dokploy/traefik"
    Invoke-WslRootCommandChecked "install -d -m 750 $traefikDir"

    $configBuilder = New-Object System.Text.StringBuilder
    $null = $configBuilder.AppendLine("entryPoints:")
    $null = $configBuilder.AppendLine("  web:")
    $null = $configBuilder.AppendLine("    address: \":$HttpPort\"")
    if ($TlsEnabled) {
        $null = $configBuilder.AppendLine("    http:")
        $null = $configBuilder.AppendLine("      redirections:")
        $null = $configBuilder.AppendLine("        entryPoint:")
        $null = $configBuilder.AppendLine("          to: websecure")
        $null = $configBuilder.AppendLine("          scheme: https")
    }
    $null = $configBuilder.AppendLine("  websecure:")
    $null = $configBuilder.AppendLine("    address: \":$HttpsPort\"")

    $null = $configBuilder.AppendLine()
    $null = $configBuilder.AppendLine("providers:")
    $null = $configBuilder.AppendLine("  docker:")
    $null = $configBuilder.AppendLine("    swarmMode: true")
    $null = $configBuilder.AppendLine("    watch: true")
    $null = $configBuilder.AppendLine("    endpoint: \"unix:///var/run/docker.sock\"")
    $null = $configBuilder.AppendLine("    exposedByDefault: false")

    if ($TlsEnabled) {
        if (-not $AcmeEmail -or -not $AcmeDnsProvider) {
            throw "TLS is enabled but ACME email or DNS provider is missing"
        }
        $null = $configBuilder.AppendLine()
        $null = $configBuilder.AppendLine("certificatesResolvers:")
        $null = $configBuilder.AppendLine("  dns01:")
        $null = $configBuilder.AppendLine("    acme:")
        $null = $configBuilder.AppendLine("      email: $AcmeEmail")
        $null = $configBuilder.AppendLine("      storage: /etc/dokploy/traefik/acme.json")
        $null = $configBuilder.AppendLine("      dnsChallenge:")
        $null = $configBuilder.AppendLine("        provider: $AcmeDnsProvider")

        Invoke-WslRootCommandChecked "install -d -m 750 $traefikDir && touch $traefikDir/acme.json && chmod 600 $traefikDir/acme.json"
    }

    $traefikConfig = $configBuilder.ToString()
    $traefikBase64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($traefikConfig))
    $escapedBase64 = $traefikBase64.Replace("'", "'\''")
    Invoke-WslRootCommandChecked "env CFG_B64='$escapedBase64' sh -lc 'printf \"%s\" \"\$CFG_B64\" | base64 -d > $traefikDir/traefik.yml && chmod 640 $traefikDir/traefik.yml'"
}

function Ensure-Secrets {
    $secretsDir = "/etc/dokploy/secrets"
    Invoke-WslRootCommandChecked "install -d -m 750 $secretsDir"

    $existingBase64 = (wsl -d $Distro -u root -e sh -lc "if [ -f $secretsDir/postgres_password ]; then base64 -w0 $secretsDir/postgres_password; fi" 2>$null)
    if ([string]::IsNullOrWhiteSpace($existingBase64)) {
        $password = New-RandomPassword
        $passwordBase64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($password))
    } else {
        $passwordBase64 = $existingBase64.Trim()
        $passwordBytes = [Convert]::FromBase64String($passwordBase64)
        $password = [Text.Encoding]::UTF8.GetString($passwordBytes)
    }

    $escapedPassword = $passwordBase64.Replace("'", "'\''")

    Invoke-WslRootCommandChecked "env PW_B64='$escapedPassword' sh -lc 'umask 0177; printf \"%s\" \"\$PW_B64\" | base64 -d > $secretsDir/postgres_password'"
    Invoke-WslRootCommand "docker secret rm dokploy_postgres_password >/dev/null 2>&1 || true" | Out-Null
    Invoke-WslRootCommandChecked "env PW_B64='$escapedPassword' sh -lc 'printf \"%s\" \"\$PW_B64\" | base64 -d | docker secret create dokploy_postgres_password -'"

    return $password
}

function Ensure-DokployEnvFile {
    param([string]$PostgresPassword)

    $escapedPassword = [System.Uri]::EscapeDataString($PostgresPassword)
    $databaseUrl = "postgresql://dokploy:$escapedPassword@dokploy-postgres:5432/dokploy"
    $envContent = "DATABASE_URL=$databaseUrl`nTZ=UTC`n"
    $envBase64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($envContent))
    $escapedEnvBase64 = $envBase64.Replace("'", "'\''")
    Invoke-WslRootCommandChecked "env ENV_B64='$escapedEnvBase64' sh -lc 'install -d -m 750 /etc/dokploy && umask 0027; printf \"%s\" \"\$ENV_B64\" | base64 -d > /etc/dokploy/dokploy.env'"

    return $databaseUrl
}

function Test-WslPorts {
    param([int[]]$Ports)
    $pattern = ($Ports | ForEach-Object { ":$_" }) -join "|"
    $output = wsl -d $Distro -e sh -lc "ss -ltnp | grep -E '($pattern)' || true" 2>$null
    if ([string]::IsNullOrWhiteSpace($output)) {
        Write-Warning "No listeners detected inside WSL for ports: $($Ports -join ', ')"
    } else {
        Write-Host "WSL listeners:" -ForegroundColor Cyan
        $output.Trim().Split("`n") | ForEach-Object { Write-Host "  $_" }
    }
}

function Assert-Systemd {
    Invoke-WslRootCommand "test -d /run/systemd/system" | Out-Null
    $exitCode = $LASTEXITCODE
    if ($exitCode -ne 0) {
        throw "WSL distro lacks systemd. Set [boot] systemd=true and restart WSL."
    }
}

function Start-Docker {
    Invoke-WslRootCommand "systemctl is-active docker || (systemctl enable docker && systemctl start docker)" | Out-Null
    $exitCode = $LASTEXITCODE
    if ($exitCode -ne 0) {
        throw "Failed to start Docker via systemd"
    }
}

function Wait-ForDocker {
    Invoke-WslRootCommandChecked "until docker info >/dev/null 2>&1; do sleep 1; done"
}

function Get-RouterRule {
    if (-not $RouterHosts -or $RouterHosts.Count -eq 0) {
        throw "RouterHosts must contain at least one host name"
    }
    $backtick = [char]0x60
    $hostRules = $RouterHosts | ForEach-Object { "Host($backtick$_$backtick)" }
    return [string]::Join(" || ", $hostRules)
}

function Deploy-PostgresService {
    $postgresCommand = @(
        "docker service create",
        "--name dokploy-postgres",
        "--replicas 1",
        "--network dokploy-network",
        "--secret source=dokploy_postgres_password,target=dokploy_postgres_password",
        "--mount type=volume,source=dokploy-postgres,target=/var/lib/postgresql/data",
        "--constraint node.role==manager",
        "--env POSTGRES_DB=dokploy",
        "--env POSTGRES_USER=dokploy",
        "--env POSTGRES_PASSWORD_FILE=/run/secrets/dokploy_postgres_password",
        "--health-cmd 'pg_isready -U dokploy -h 127.0.0.1 -d dokploy'",
        "--health-interval 10s",
        "--health-retries 5",
        "postgres:16-alpine"
    ) -join ' '
    Invoke-WslRootCommandChecked $postgresCommand | Out-Null
}

function Deploy-DokployService {
    param([string]$RouterRule)

    $dokployCommandArgs = [System.Collections.Generic.List[string]]::new()
    $dokployCommandArgs.Add("docker service create") | Out-Null
    $dokployCommandArgs.Add("--name dokploy") | Out-Null
    $dokployCommandArgs.Add("--replicas 1") | Out-Null
    $dokployCommandArgs.Add("--network dokploy-network") | Out-Null
    $dokployCommandArgs.Add("--mount type=bind,source=/var/run/docker.sock,target=/var/run/docker.sock") | Out-Null
    $dokployCommandArgs.Add("--secret source=dokploy_postgres_password,target=dokploy_postgres_password") | Out-Null
    $dokployCommandArgs.Add("--env-file /etc/dokploy/dokploy.env") | Out-Null
    $dokployCommandArgs.Add("--publish published=3000,target=3000,mode=host") | Out-Null
    $dokployCommandArgs.Add("--constraint node.role==manager") | Out-Null
    $dokployCommandArgs.Add("--label traefik.enable=true") | Out-Null
    $dokployCommandArgs.Add("--label 'traefik.http.routers.dokploy.rule=$RouterRule'") | Out-Null
    $dokployCommandArgs.Add("--label traefik.http.routers.dokploy.entrypoints=web,websecure") | Out-Null
    $dokployCommandArgs.Add("--label traefik.http.services.dokploy.loadbalancer.server.port=3000") | Out-Null
    if ($EnableTls) {
        $dokployCommandArgs.Add("--label traefik.http.routers.dokploy.tls=true") | Out-Null
        $dokployCommandArgs.Add("--label traefik.http.routers.dokploy.tls.certresolver=dns01") | Out-Null
    }
    $dokployCommandArgs.Add("--health-cmd 'wget -qO- http://127.0.0.1:3000/healthz || exit 1'") | Out-Null
    $dokployCommandArgs.Add("--health-interval 10s") | Out-Null
    $dokployCommandArgs.Add("--health-retries 12") | Out-Null
    $dokployCommandArgs.Add("dokploy/dokploy:latest") | Out-Null
    $dokployCommand = [string]::Join(' ', $dokployCommandArgs)
    Invoke-WslRootCommandChecked $dokployCommand | Out-Null
}

function Deploy-TraefikService {
    $traefikCommandArgs = [System.Collections.Generic.List[string]]::new()
    $traefikCommandArgs.Add("docker service create") | Out-Null
    $traefikCommandArgs.Add("--name dokploy-traefik") | Out-Null
    $traefikCommandArgs.Add("--network dokploy-network") | Out-Null
    $traefikCommandArgs.Add("--constraint node.role==manager") | Out-Null
    $traefikCommandArgs.Add("--mount type=bind,source=/var/run/docker.sock,target=/var/run/docker.sock") | Out-Null
    $traefikCommandArgs.Add("--mount type=bind,source=/etc/dokploy/traefik/traefik.yml,target=/etc/traefik/traefik.yml,readonly") | Out-Null
    if ($EnableTls) {
        $traefikCommandArgs.Add("--mount type=bind,source=/etc/dokploy/traefik/acme.json,target=/etc/traefik/acme.json") | Out-Null
    }
    $traefikCommandArgs.Add("--publish published=$HttpPort,target=80,mode=host") | Out-Null
    $traefikCommandArgs.Add("--publish published=$HttpsPort,target=443,mode=host") | Out-Null
    $traefikCommandArgs.Add("traefik:v3.5.0") | Out-Null
    $traefikCommand = [string]::Join(' ', $traefikCommandArgs)
    Invoke-WslRootCommandChecked $traefikCommand | Out-Null
}

function Wait-ForServiceRemoval {
    param([string[]]$Names)
    foreach ($name in $Names) {
        Invoke-WslRootCommandChecked "while docker service inspect $name >/dev/null 2>&1; do sleep 1; done"
    }
}

function Register-PortProxyTask {
    $action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-NoProfile -WindowStyle Hidden -File `"$PSCommandPath`" -Rebind"
    $triggers = @(New-ScheduledTaskTrigger -AtStartup, New-ScheduledTaskTrigger -AtLogOn)
    Register-ScheduledTask -TaskName "Dokploy-RebindPorts" -Action $action -Trigger $triggers -RunLevel Highest -Force | Out-Null
}

if ($Rebind) {
    Configure-PortProxy -Ports @($HttpPort,$HttpsPort,3000)
    exit
}

function Install-Dokploy {
    Write-Host "Starting Dokploy installation..." -ForegroundColor Green

    $isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")
    if (-not $isAdmin) {
        Write-Error "This script must be run as Administrator."; return
    }

    try {
        wsl --status 2>$null | Out-Null
    } catch {
        Write-Error "WSL2 is not installed. Please install WSL2 and a Linux distribution."; return
    }

    Assert-Systemd

    $dockerExists = wsl -d $Distro -e sh -lc "command -v docker" 2>$null
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Docker is not installed in WSL. Install Docker in your $Distro distribution."; return
    }

    Test-PortFree $HttpPort
    Test-PortFree $HttpsPort
    Test-PortFree 3000

    Start-Docker
    Wait-ForDocker

    Ensure-TraefikConfig -TlsEnabled:$EnableTls

    Invoke-WslRootCommand "docker service rm dokploy dokploy-traefik dokploy-postgres >/dev/null 2>&1 || true" | Out-Null
    Invoke-WslRootCommand "docker stack rm dokploy >/dev/null 2>&1 || true" | Out-Null
    Wait-ForServiceRemoval -Names @("dokploy","dokploy-traefik","dokploy-postgres")
    Invoke-WslRootCommand "docker swarm leave --force >/dev/null 2>&1 || true" | Out-Null

    $wslIp = Get-WslIp
    Invoke-WslRootCommandChecked "docker swarm init --advertise-addr $wslIp >/dev/null 2>&1"
    Wait-ForDocker

    Invoke-WslRootCommand "docker network create --driver overlay --attachable dokploy-network >/dev/null 2>&1 || true" | Out-Null
    Invoke-WslRootCommand "docker volume create dokploy-postgres >/dev/null 2>&1 || true" | Out-Null

    $postgresPassword = Ensure-Secrets
    Ensure-DokployEnvFile -PostgresPassword $postgresPassword | Out-Null

    Invoke-WslRootCommandChecked "docker pull dokploy/dokploy:latest"
    Invoke-WslRootCommandChecked "docker pull traefik:v3.5.0"
    Invoke-WslRootCommandChecked "docker pull postgres:16-alpine"

    $routerRule = Get-RouterRule

    Deploy-PostgresService
    Deploy-DokployService -RouterRule $routerRule
    Deploy-TraefikService

    Configure-PortProxy -Ports @($HttpPort,$HttpsPort,3000)
    Register-PortProxyTask
    Test-WslPorts -Ports @($HttpPort,$HttpsPort,3000)

    Write-Host "Dokploy has been deployed. Ports $HttpPort (HTTP), $HttpsPort (HTTPS) and 3000 (Admin UI) are forwarded to WSL." -ForegroundColor Green
}

function Update-Dokploy {
    Write-Host "Updating Dokploy..." -ForegroundColor Green

    Assert-Systemd

    Start-Docker
    Wait-ForDocker

    $postgresPassword = Ensure-Secrets
    Ensure-DokployEnvFile -PostgresPassword $postgresPassword | Out-Null
    Ensure-TraefikConfig -TlsEnabled:$EnableTls

    Invoke-WslRootCommandChecked "docker pull dokploy/dokploy:latest"
    Invoke-WslRootCommandChecked "docker pull traefik:v3.5.0"
    Invoke-WslRootCommandChecked "docker pull postgres:16-alpine"

    $routerRule = Get-RouterRule

    Invoke-WslRootCommand "docker service rm dokploy dokploy-traefik >/dev/null 2>&1 || true" | Out-Null
    Wait-ForServiceRemoval -Names @("dokploy","dokploy-traefik")

    Deploy-DokployService -RouterRule $routerRule
    Deploy-TraefikService

    Invoke-WslRootCommandChecked "docker service update --image postgres:16-alpine dokploy-postgres" | Out-Null

    Configure-PortProxy -Ports @($HttpPort,$HttpsPort,3000)
    Register-PortProxyTask
    Test-WslPorts -Ports @($HttpPort,$HttpsPort,3000)

    Write-Host "Dokploy updated." -ForegroundColor Green
}

if ($Update) { Update-Dokploy } else { Install-Dokploy }
