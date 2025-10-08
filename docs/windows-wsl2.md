# Windows / WSL2 deployment guide

This document describes how to deploy Dokploy on a Windows Server 2022 or
Windows 11 host using WSL2.  The goal is to run the Linux containers inside
WSL while exposing HTTP/HTTPS and admin ports on the Windows host.

## Prerequisites

1. Enable **WSL2** and install a Linux distribution (Ubuntu 22.04 is the default).
   Refer to Microsoft’s documentation for enabling WSL on Windows Server 2022.
2. Install **Docker** in your WSL distribution.  Docker Desktop is not
   necessary; you can install the Docker engine inside WSL and run it via
   `systemd`.
3. Run PowerShell as an administrator when executing scripts.

## Installation

Use the provided PowerShell script to install Dokploy and Traefik inside WSL and
set up port forwarding.  The script will:

* Verify that you are running as an administrator and that WSL and Docker are
  available.
* Start Docker via `systemd` in the WSL distribution.
* Initialise a single‑node Docker Swarm and create an overlay network.
* Deploy the Dokploy service and a Traefik reverse proxy as Swarm services.
* Set up Windows `portproxy` rules to forward ports 80, 443 and 3000 from the
  Windows host to the WSL IP address.
* Open firewall rules on the Windows host to allow inbound traffic on the
  configured ports.

Run the installer:

```powershell
Set-ExecutionPolicy Bypass -Scope Process -Force
./scripts/install.ps1
```

After installation completes you can access the Dokploy admin UI at
`http://localhost:3000` on your Windows machine.  The public HTTP and HTTPS
endpoints are forwarded to the WSL instance via portproxy.

## Updating Dokploy

To update Dokploy to the latest image run the script with `-Update`:

```powershell
./scripts/install.ps1 -Update
```

This will pull the latest image and update the running service.  Port
forwarding rules are refreshed automatically.

## Considerations

* The WSL IP address can change when you restart the distribution or reboot
  Windows.  The script re‑applies portproxy rules based on the current IP.
* This setup uses a basic Traefik configuration.  For production use you
  should supply your own `traefik.yml` and enable ACME certificates.
* Windows Server does not officially support Docker Desktop; running Docker
  inside WSL is a workaround that is suitable for development and testing.
