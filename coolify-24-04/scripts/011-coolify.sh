#!/bin/bash

set -euo pipefail

log() {
  local level="$1"; shift
  echo "[$(date -u +'%Y-%m-%dT%H:%M:%SZ')] [$level] $*"
}

export DEBIAN_FRONTEND=noninteractive

wait_for_apt() {
  local tries=0
  while fuser /var/lib/dpkg/lock-frontend /var/lib/dpkg/lock /var/lib/apt/lists/lock /var/cache/apt/archives/lock >/dev/null 2>&1; do
    tries=$((tries + 1))
    if [ "$tries" -gt 60 ]; then
      log WARN "apt/dpkg lock still held after 5 minutes; continuing anyway."
      break
    fi
    log INFO "Waiting for apt/dpkg lock to be released..."
    sleep 5
  done
}

log INFO "Waiting for any background apt/cloud-init operations to finish..."
systemctl stop unattended-upgrades.service >/dev/null 2>&1 || true
wait_for_apt

log INFO "Updating base packages..."
apt-get update -y
apt-get -y -o Dpkg::Options::='--force-confdef' -o Dpkg::Options::='--force-confold' upgrade

log INFO "Installing system dependencies..."
apt-get install -y \
  apt-transport-https \
  ca-certificates \
  curl \
  git \
  gnupg \
  jq \
  lsb-release \
  net-tools \
  openssl \
  software-properties-common \
  wget \
  ufw

log INFO "Configuring official Docker repository..."
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
chmod a+r /etc/apt/keyrings/docker.gpg
ARCH=$(dpkg --print-architecture)
CODENAME=$(grep VERSION_CODENAME /etc/os-release | cut -d= -f2)
echo \
  "deb [arch=${ARCH} signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu ${CODENAME} stable" \
  > /etc/apt/sources.list.d/docker.list

log INFO "Installing Docker Engine and Compose plugins..."
apt-get update -y
set +e
apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
if [ "$?" -ne 0 ]; then
  log WARN "Failed to install Docker CE; falling back to distro docker.io package"
  apt-get install -y docker.io
fi
set -e

log INFO "Configuring Docker daemon logging limits..."
mkdir -p /etc/docker
cat > /etc/docker/daemon.json <<'EOF'
{
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  }
}
EOF

systemctl enable docker
systemctl restart docker
usermod -aG docker root || true

log INFO "Pre-configuring UFW firewall rules for Coolify..."
# Rules are staged now and enabled on first boot (onboot) to avoid locking Packer's SSH session.
ufw allow 22/tcp    # SSH
ufw allow 80/tcp    # HTTP / Let's Encrypt
ufw allow 443/tcp   # HTTPS
ufw allow 8000/tcp  # Coolify dashboard
ufw allow 6001/tcp  # Coolify realtime
ufw allow 6002/tcp  # Coolify Soketi (websocket)

log INFO "Creating Coolify directory structure under /data/coolify..."
mkdir -p /data/coolify/{source,ssh,applications,databases,backups,services,proxy,webhooks-during-maintenance}
mkdir -p /data/coolify/ssh/{keys,mux}
mkdir -p /data/coolify/proxy/dynamic

log INFO "Downloading Coolify configuration files from the official CDN..."
# Secrets are still placeholders here; they are rotated per-instance on first boot.
curl -fsSL https://cdn.coollabs.io/coolify/docker-compose.yml      -o /data/coolify/source/docker-compose.yml
curl -fsSL https://cdn.coollabs.io/coolify/docker-compose.prod.yml -o /data/coolify/source/docker-compose.prod.yml
curl -fsSL https://cdn.coollabs.io/coolify/.env.production         -o /data/coolify/source/.env
curl -fsSL https://cdn.coollabs.io/coolify/upgrade.sh             -o /data/coolify/source/upgrade.sh

log INFO "Setting ownership and permissions on /data/coolify..."
chown -R 9999:root /data/coolify
chmod -R 700 /data/coolify

log INFO "Creating the attachable Docker network 'coolify'..."
docker network create --attachable coolify 2>/dev/null || true

log INFO "Enabling the Coolify systemd service (started on first boot)..."
systemctl daemon-reload
systemctl enable coolify.service || true

log INFO "Making helper, MOTD and onboot scripts executable..."
for f in \
  /opt/start-coolify.sh \
  /opt/stop-coolify.sh \
  /opt/restart-coolify.sh \
  /opt/update-coolify.sh \
  /opt/coolify-logs.sh \
  /opt/coolify-status.sh \
  /opt/coolify_localhost_setup.sh \
  /opt/configure-coolify-localhost.sh \
  /etc/update-motd.d/99-startup \
  /var/lib/cloud/scripts/per-instance/001_onboot; do
  [ -f "$f" ] && chmod +x "$f"
done

log INFO "Coolify build-time preparation completed."
log INFO "Secrets are rotated and containers are started on first boot via 001_onboot."
