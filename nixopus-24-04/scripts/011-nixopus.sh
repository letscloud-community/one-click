#!/bin/bash

set -euo pipefail

log() {
  local level="$1"; shift
  echo "[$(date -u +'%Y-%m-%dT%H:%M:%SZ')] [$level] $*"
}

export DEBIAN_FRONTEND=noninteractive

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
  software-properties-common \
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

systemctl enable --now docker
usermod -aG docker root || true

log INFO "Creating Nixopus directories..."
mkdir -p /opt/nixopus /var/log/nixopus

# Ensure cloud-init onboot script is executable (required for SSH unlock)
if [ -f /var/lib/cloud/scripts/per-instance/001_onboot ]; then
  chmod +x /var/lib/cloud/scripts/per-instance/001_onboot
fi

log INFO "Dependencies installation completed."
log INFO "Nixopus will be installed on first boot using the official installer."
log INFO "This ensures the latest version is always installed."

