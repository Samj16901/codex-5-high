# Windows / WSL2 deployment guide

This document describes how to deploy Dokploy on a Windows Server 2022 or
Windows 11 host using WSL2.  The goal is to run the Linux containers inside
WSL while exposing HTTP/HTTPS and admin ports on the Windows host.

## Prerequisites

1. Enable **WSL2** and install a Linux distribution (Ubuntu 22.04 is the default).
   Refer to Microsoft’s documentation for enabling WSL on Windows Server 2022.
2. Ensure the distribution starts with **systemd** enabled (set `[boot] systemd=true`
   in `/etc/wsl.conf` and restart WSL if needed).
3. Install **Docker** in your WSL distribution.  Docker Desktop is not
   necessary; install the Docker engine inside WSL and manage it with
   `systemd`.
4. Run PowerShell as an administrator when executing scripts.

## Installation

Use the provided PowerShell script to install Dokploy and Traefik inside WSL and
set up port forwarding.  The script will:

* Verify administrator privileges, ensure WSL/systemd/Docker are available and
  guard the Windows host ports (80/443/3000 by default) before creating
  `portproxy` bindings.
* Start Docker via `systemd`, wait for the daemon to be ready and initialise a
  single-node Docker Swarm.
* Create an overlay network, persistent Postgres volume and Docker secret for a
  randomly generated Postgres password.
* Generate `/etc/dokploy/dokploy.env` (mode `640`) with a secret-backed
  `DATABASE_URL` and write `/etc/dokploy/traefik/traefik.yml` (mode `640`).
* Deploy Postgres, Dokploy and Traefik as Swarm services with health checks,
  Traefik labels scoped to your configured hostnames and optional TLS via ACME
  DNS challenges.
* Create Windows firewall rules, `portproxy` forwards (80/443/3000 by default)
  and a scheduled task that rebinds the proxies on boot or logon so that WSL IP
  changes are handled automatically.
* Validate that listeners are active inside WSL after deployment.

Run the installer:

```powershell
Set-ExecutionPolicy Bypass -Scope Process -Force
./scripts/install.ps1 -RouterHosts dokploy.local
```

The `-RouterHosts` parameter accepts one or more hostnames used by Traefik for
routing (e.g. `-RouterHosts dokploy.local,apps.example.com`).  Ports can be
customised with `-HttpPort`/`-HttpsPort`.

### Enabling TLS with ACME DNS-01

To request certificates automatically, enable TLS and provide the ACME
configuration:

```powershell
./scripts/install.ps1 -RouterHosts dokploy.example.com -EnableTls -AcmeEmail you@example.com -AcmeDnsProvider cloudflare
```

The script creates `/etc/dokploy/traefik/acme.json` (mode `600`), configures
Traefik’s DNS-01 resolver and redirects HTTP to HTTPS.  Supply the provider’s
credentials via environment variables or files according to Traefik’s DNS
provider documentation before running the installer.

## Updating Dokploy

To update Dokploy to the latest image run the script with `-Update` (the same
routing/TLS parameters apply):

```powershell
./scripts/install.ps1 -Update -RouterHosts dokploy.local
```

This will refresh images, secrets, Traefik configuration, health checks and
port-forwarding rules.  The scheduled task is re-registered to ensure future
WSL IP changes are handled.

## Considerations

* The scheduled task re-applies `portproxy` rules on startup/logon, but you can
  trigger it manually with `./scripts/install.ps1 -Rebind` if required.
* If another service is already listening on your chosen HTTP/HTTPS/UI ports,
  the installer fails fast so you can release the port or adjust the bindings.
* For production scenarios you should secure Traefik further (mTLS, access
  control, secret management) and consider publishing Dokploy behind an
  additional reverse proxy such as IIS if it already runs on the host.
