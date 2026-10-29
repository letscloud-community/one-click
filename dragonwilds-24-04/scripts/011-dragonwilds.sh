#!/bin/bash
#
# Build-time preparation for the RuneScape: Dragonwilds one-click image.
#
# This stage installs everything that is identical on every instance and
# deliberately does NOT start the server: the Owner ID is unique per customer
# and is only known on the first boot. See files/.../001_onboot and
# /opt/dragonwilds/scripts/first-boot.sh for the runtime stage.

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

# No full upgrade here on purpose. The system is brought up to date earlier by
# scripts/005-system-upgrade.sh, which runs detached from the SSH session.
# Upgrading hundreds of packages from this provisioner would restart sshd and
# drop Packer's connection.
log INFO "Refreshing the package index..."
apt-get update -y

log INFO "Installing system dependencies..."
apt-get install -y \
  apt-transport-https \
  ca-certificates \
  conntrack \
  curl \
  gnupg \
  jq \
  logrotate \
  lsb-release \
  net-tools \
  openssl \
  software-properties-common \
  tar \
  ufw \
  wget

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
  apt-get install -y docker.io docker-compose-v2
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
  },
  "live-restore": true
}
EOF

systemctl enable docker
systemctl restart docker

log INFO "Creating the directory structure under /opt/dragonwilds..."
mkdir -p /opt/dragonwilds/data
mkdir -p /opt/dragonwilds/backups/{hourly,daily,weekly,manual,pre-update,pre-restore}
mkdir -p /opt/dragonwilds/scripts
mkdir -p /var/log/dragonwilds
mkdir -p /var/lib/dragonwilds

# The official image runs as uid/gid 1000 and cannot chown its own bind mount,
# so the host has to hand it a writable directory.
chown -R 1000:1000 /opt/dragonwilds/data
chmod 0750 /opt/dragonwilds/data
chmod 0700 /opt/dragonwilds/backups
chmod 0750 /var/log/dragonwilds
chmod 0750 /var/lib/dragonwilds
chmod 0755 /opt/dragonwilds

log INFO "Pre-pulling the official Jagex server image..."
# Only the container image (about 500 MB) is cached here. The ~5.5 GB game
# itself is downloaded by SteamCMD on the first start, which keeps the snapshot
# small and guarantees customers always begin on the current build.
if ! docker pull ghcr.io/runescape/rsdw-dedicated:latest; then
  log WARN "Could not pre-pull the image; first-boot.sh will fetch it instead."
fi

log INFO "Pre-configuring UFW firewall rules..."
# Rules are staged now and the firewall is only enabled on the first boot, so
# that enabling it here cannot cut Packer's own SSH session.
ufw default deny incoming
ufw default allow outgoing
ufw allow 22/tcp comment 'SSH'
ufw allow 7777/udp comment 'RuneScape Dragonwilds game'
# The beacon port is what the Worlds browser uses to advertise and reach the
# server. Without it the world is listed and every join ends in
# "connection lost".
ufw allow 8888/udp comment 'RuneScape Dragonwilds beacon'

# Confirm the SSH rule was actually stored in the image. Without it the first
# boot would enable a deny-by-default firewall with no way back in.
if ufw show added | grep -qE '(^|[[:space:]])22/tcp([[:space:]]|$)'; then
  log INFO "SSH rule present in the staged ruleset."
else
  log ERROR "The SSH rule is missing from the staged ruleset; aborting the build."
  ufw show added || true
  exit 1
fi

log INFO "Making the management scripts executable..."
chmod 0755 /opt/dragonwilds/scripts/*.sh
chmod 0644 /opt/dragonwilds/docker-compose.yml
chmod 0644 /opt/dragonwilds/env.example
chmod 0644 /etc/logrotate.d/dragonwilds
# Sourced by /etc/profile, so it only needs to be readable.
chmod 0644 /etc/profile.d/dragonwilds-first-boot.sh
for f in \
  /etc/update-motd.d/99-startup \
  /var/lib/cloud/scripts/per-instance/001_onboot; do
  [ -f "$f" ] && chmod +x "$f"
done

log INFO "Verifying that the files needed on first boot are present..."
for f in \
  /opt/dragonwilds/scripts/first-boot.sh \
  /opt/dragonwilds/scripts/firewall.sh \
  /opt/dragonwilds/docker-compose.yml \
  /opt/dragonwilds/env.example \
  /etc/profile.d/dragonwilds-first-boot.sh \
  /var/lib/cloud/scripts/per-instance/001_onboot; do
  if [ ! -f "$f" ]; then
    log ERROR "Missing required file: $f"
    exit 1
  fi
done

log INFO "Enabling the systemd units (they stay inert until .env exists)..."
systemctl daemon-reload
systemctl enable dragonwilds.service || true
systemctl enable dragonwilds-backup.timer || true
systemctl enable dragonwilds-update.timer || true

log INFO "Validating the compose file..."
docker compose -f /opt/dragonwilds/docker-compose.yml --env-file /opt/dragonwilds/env.example config -q \
  || log WARN "Compose validation reported a problem; review docker-compose.yml."

log INFO "Build-time preparation completed."
log INFO "The Owner ID is collected and the server is started on first boot."
