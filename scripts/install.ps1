# Dokploy installation script for Windows with WSL2
#
# This script provisions Dokploy inside a WSL2 distribution and exposes its
# ports on the Windows host.  It is intended for Windows Server 2022 or
# Windows 11 systems with WSL2 enabled.  Run this script as an administrator.

param(
    [switch]$Update,
    [string]$Distro = "Ubuntu-22.04",
    [int]$HttpPort = 8080,
    [int]$HttpsPort = 8443
)

function Get-WslIp {
    # Determine the IPv4 address of eth0 inside the WSL distribution.
    $ip = wsl -d $Distro -e sh -lc "ip -4 addr show eth0 | awk '/inet /{print \$2}' | cut -d/ -f1" 2>$null
    return $ip.Trim()
}

function Configure-PortProxy {
    param([int[]]$Ports)
    $wslIp = Get-WslIp
    foreach ($p in $Ports) {
        # Remove any existing proxy for the port
        netsh interface portproxy delete v4tov4 listenport=$p protocol=tcp 2>$null | Out-Null
        # Create portproxy from Windows to WSL
        netsh interface portproxy add v4tov4 listenaddress=0.0.0.0 listenport=$p connectaddress=$wslIp connectport=$p protocol=tcp | Out-Null
        # Open firewall rule
        New-NetFirewallRule -DisplayName "Dokploy-$p" -Direction Inbound -Action Allow -Protocol TCP -LocalPort $p -ErrorAction SilentlyContinue | Out-Null
    }
}

function Start-Docker {
    # Start Docker inside WSL.  Works for distributions with systemd.
    wsl -d $Distro -e sh -lc "systemctl is-active docker || (sudo systemctl enable docker && sudo systemctl start docker)" | Out-Null
}

function Install-Dokploy {
    Write-Host "Starting Dokploy installation..." -ForegroundColor Green

    # Require admin
    $isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")
    if (-not $isAdmin) {
        Write-Error "This script must be run as Administrator."; return
    }

    # Verify WSL
    try {
        wsl --status 2>$null | Out-Null
    } catch {
        Write-Error "WSL2 is not installed. Please install WSL2 and a Linux distribution."; return
    }

    # Verify Docker command inside WSL
    $dockerExists = wsl -d $Distro -e sh -lc "command -v docker" 2>$null
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Docker is not installed in WSL. Install Docker in your $Distro distribution."; return
    }

    # Ensure Docker is running
    Start-Docker

    # Initialise Swarm (optional) and network
    wsl -d $Distro -e sh -lc "docker swarm leave --force 2>/dev/null || true" | Out-Null
    $wslIp = Get-WslIp
    wsl -d $Distro -e sh -lc "docker swarm init --advertise-addr $wslIp || true" | Out-Null
    wsl -d $Distro -e sh -lc "docker network create --driver overlay --attachable dokploy-network || true" | Out-Null

    # Pull images
    wsl -d $Distro -e sh -lc "docker pull dokploy/dokploy:latest" | Out-Null
    wsl -d $Distro -e sh -lc "docker pull traefik:v3.5.0" | Out-Null

    # Deploy Dokploy service
    wsl -d $Distro -e sh -lc "docker service create --name dokploy --replicas 1 --network dokploy-network --mount type=bind,source=/var/run/docker.sock,target=/var/run/docker.sock --publish published=3000,target=3000,mode=host dokploy/dokploy:latest" | Out-Null

    # Deploy Traefik as a service on ports 80/443 inside WSL
    wsl -d $Distro -e sh -lc "docker service create --name dokploy-traefik --network dokploy-network --publish published=80,target=80,mode=host --publish published=443,target=443,mode=host -v /var/run/docker.sock:/var/run/docker.sock traefik:v3.5.0 --providers.docker.swarmMode=true --entrypoints.web.address=\":80\" --entrypoints.websecure.address=\":443\"" | Out-Null

    # Expose ports to Windows via portproxy
    Configure-PortProxy -Ports @($HttpPort,$HttpsPort,3000)

    Write-Host "Dokploy has been deployed.  Ports $HttpPort (HTTP), $HttpsPort (HTTPS) and 3000 (Admin UI) are forwarded to WSL." -ForegroundColor Green
}

function Update-Dokploy {
    Write-Host "Updating Dokploy..." -ForegroundColor Green
    wsl -d $Distro -e sh -lc "docker pull dokploy/dokploy:latest" | Out-Null
    wsl -d $Distro -e sh -lc "docker service update --image dokploy/dokploy:latest dokploy" | Out-Null
    Write-Host "Dokploy updated." -ForegroundColor Green
    Configure-PortProxy -Ports @($HttpPort,$HttpsPort,3000)
}

if ($Update) { Update-Dokploy } else { Install-Dokploy }