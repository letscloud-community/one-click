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

INSTALLER_PATH="/tmp/nixopus-install.sh"
log INFO "Downloading official Nixopus installer..."
curl -fsSL https://install.nixopus.com -o "${INSTALLER_PATH}"
chmod +x "${INSTALLER_PATH}"

PUBLIC_IP="$(curl -fsSL https://ifconfig.me 2>/dev/null || curl -fsSL https://api.ipify.org 2>/dev/null || hostname -I | awk '{print $1}')"
NIXOPUS_ARGS=(
  "--force"
  "--timeout" "900"
  "--api-port" "8443"
  "--view-port" "7443"
)

if [ -n "${PUBLIC_IP:-}" ]; then
  NIXOPUS_ARGS+=("--host-ip" "${PUBLIC_IP}")
fi

log INFO "Running the Nixopus installer (this can take a few minutes)..."
INSTALL_LOG="/var/log/nixopus/install.log"
: > "${INSTALL_LOG}"
attempt=1
max_attempts=3
until bash "${INSTALLER_PATH}" "${NIXOPUS_ARGS[@]}" 2>&1 | tee -a "${INSTALL_LOG}"; do
  if [ "$attempt" -ge "$max_attempts" ]; then
    log ERROR "Nixopus installation failed after ${max_attempts} attempts. Check ${INSTALL_LOG}."
    exit 1
  fi
  attempt=$((attempt + 1))
  log WARN "Retrying Nixopus installation (attempt ${attempt}/${max_attempts}) in 15s..."
  sleep 15
done

if ! command -v nixopus >/dev/null 2>&1; then
  log ERROR "The 'nixopus' binary was not found after installation."
  exit 1
fi

log INFO "Installed Nixopus version: $(nixopus --version 2>/dev/null || echo 'unknown')"

log INFO "Firewall configuration: Please configure ufw manually to allow required ports:"
log INFO "  - SSH: 22/tcp"
log INFO "  - Caddy: 80/tcp (HTTP), 443/tcp (HTTPS), 2019/tcp (Admin)"
log INFO "  - Nixopus: 7443/tcp (Frontend), 8443/tcp (API)"
log INFO "  - Database: 5432/tcp (PostgreSQL), 6379/tcp (Redis)"
log INFO "  - Auth: 3567/tcp (SuperTokens)"
log INFO "Example: ufw allow 22/tcp && ufw allow 80/tcp && ufw allow 443/tcp && ufw allow 7443/tcp && ufw allow 8443/tcp && ufw allow 2019/tcp && ufw allow 3567/tcp && ufw allow 5432/tcp && ufw allow 6379/tcp && ufw --force enable"

log INFO "Creating helper script for forced reinstallation..."
cat > /usr/local/bin/nixopus-redeploy <<'EOF'
#!/bin/bash
set -euo pipefail
LOG_FILE=/var/log/nixopus/redeploy.log
mkdir -p "$(dirname "${LOG_FILE}")"
{
  echo "[$(date -Is)] Reapplying Nixopus..."
  if command -v nixopus >/dev/null 2>&1; then
    nixopus install --force --timeout 900 "$@"
  else
    echo "nixopus CLI is not installed." >&2
    exit 1
  fi
} | tee -a "${LOG_FILE}"
EOF
chmod +x /usr/local/bin/nixopus-redeploy

log INFO "Nixopus installation completed."

