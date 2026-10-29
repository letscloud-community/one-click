# Coolify One-Click (Ubuntu 24.04)

One-Click image for [Coolify](https://coolify.io), the open-source self-hosted
platform for deploying applications, databases and services (an alternative to
Heroku, Netlify and Vercel).

The image is built with Packer on top of Ubuntu 24.04 LTS and follows the phased
model: everything is prepared during the build, and the installation is finished
on first boot, generating secrets that are unique per instance.

## What the image includes

- Docker Engine (official installation) with log limits configured
- Full Coolify directory structure under `/data/coolify`
- Configuration files downloaded from Coolify's official CDN
- Pre-configured UFW firewall (22, 80, 443, 8000, 6001, 6002)
- `coolify.service` systemd unit (auto-start on boot)
- Management scripts under `/opt`
- Interactive localhost activation wizard on the first SSH login
- MOTD with access instructions

## Structure

```
coolify-24-04/
├── coolify-24-04.pkr.hcl                 # Packer build configuration
├── README.md                             # This file
├── scripts/
│   └── 011-coolify.sh                    # Build-time preparation
└── files/
    ├── etc/
    │   ├── systemd/system/
    │   │   └── coolify.service           # systemd unit
    │   └── update-motd.d/
    │       └── 99-startup                # Message of the Day
    ├── opt/
    │   ├── start-coolify.sh              # Start the containers
    │   ├── stop-coolify.sh               # Stop the containers
    │   ├── restart-coolify.sh            # Restart the containers
    │   ├── update-coolify.sh             # Update to the latest version
    │   ├── coolify-logs.sh               # Live logs
    │   ├── coolify-status.sh             # Container status
    │   ├── coolify_localhost_setup.sh    # Interactive wizard (1st login)
    │   └── configure-coolify-localhost.sh # Non-interactive localhost activation
    └── var/
        └── lib/cloud/scripts/per-instance/
            └── 001_onboot                # First-boot initialization
```

## Installation phases

**1. Build (`scripts/011-coolify.sh`)**, prepares but does not start:
- Updates the system and installs dependencies (curl, git, jq, openssl, ufw, etc.)
- Installs the official Docker Engine and configures `daemon.json`
- Creates `/data/coolify/{source,ssh,applications,databases,backups,services,proxy,...}`
- Downloads `docker-compose.yml`, `docker-compose.prod.yml`, `.env.production` and `upgrade.sh` from the CDN
- Pre-configures UFW, creates the `coolify` Docker network and enables the systemd service

**2. First boot (`001_onboot`)**, finishes and starts:
- Removes the SSH `ForceCommand` and enables UFW
- Generates a unique ed25519 SSH key (without adding it to `authorized_keys`)
- **Rotates per-instance secrets** (`APP_ID`, `APP_KEY`, `DB_PASSWORD`,
  `REDIS_PASSWORD`, `PUSHER_*`) with `openssl`
- Starts the containers with `docker compose up -d`
- Writes `/root/coolify_info.txt` and registers the localhost wizard in `.bashrc`

**3. First SSH login (`coolify_localhost_setup.sh`)**:
- Asks whether to enable the localhost server for deployments
- If yes, adds the key to `authorized_keys` and restarts Coolify
- Runs only once

## How to build

```bash
packer init coolify-24-04.pkr.hcl
packer validate -var "api_key=YOUR_TOKEN" coolify-24-04.pkr.hcl
packer build   -var "api_key=YOUR_TOKEN" coolify-24-04.pkr.hcl
```

## How to use after deployment

1. Create an instance from the snapshot (minimum 2 vCPU / 2 GB RAM / 30 GB).
2. Wait 3 to 5 minutes for the first boot to complete.
3. Open `http://YOUR_IP:8000` and **create the admin account immediately**.
4. (Optional) Enable localhost over SSH: the wizard appears on the first login,
   or run `/opt/configure-coolify-localhost.sh`.

## Firewall ports

| Port | Service | Description |
|------|---------|-------------|
| 22 | SSH | Remote access |
| 80 | HTTP | Web traffic / Let's Encrypt |
| 443 | HTTPS | Secure web traffic |
| 8000 | Coolify UI | Web interface |
| 6001 | Realtime | Real-time updates |
| 6002 | Soketi | WebSocket server |

## Minimum requirements

- CPU: 2 cores
- RAM: 2 GB
- Disk: 30 GB

For production with multiple applications, 4+ cores, 8+ GB of RAM and 100+ GB of
disk are recommended.

## Updating

```bash
/opt/update-coolify.sh
```

## Links

- Documentation: https://coolify.io/docs
- GitHub: https://github.com/coollabsio/coolify
- Community: https://coolify.io/discord
