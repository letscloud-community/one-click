#!/bin/bash

# n8n image build script for Ubuntu 24.04.
#
# Installs Docker, nginx and the n8n stack (n8n + PostgreSQL + external task
# runner) defined in /opt/n8n/docker-compose.yml.
#
# The stack is deliberately NOT started here: starting it would bake a
# credential encryption key and a database cluster into the snapshot, which
# every instance created from it would then share. n8n-init.service generates
# those secrets on first boot instead.

set -e

echo "Installing base packages..."
apt-get update
apt-get install -y ca-certificates curl wget git unzip jq openssl gnupg lsb-release nginx

# -----------------------------------------------------------------------------
# Docker
# -----------------------------------------------------------------------------
echo "Installing Docker..."
set +e
DOCKER_SETUP_OK=0
if [ ! -f /etc/apt/keyrings/docker.gpg ]; then
  install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
  chmod a+r /etc/apt/keyrings/docker.gpg
fi
ARCH=$(dpkg --print-architecture)
CODENAME=$(grep VERSION_CODENAME /etc/os-release | cut -d= -f2)
echo "deb [arch=${ARCH} signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu ${CODENAME} stable" > /etc/apt/sources.list.d/docker.list
apt-get update && apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin && DOCKER_SETUP_OK=1

if [ "$DOCKER_SETUP_OK" -ne 1 ]; then
  echo "Docker CE repo install failed; falling back to docker.io"
  apt-get install -y docker.io docker-compose || true
fi
set -e

systemctl enable --now docker

# Wrapper so the systemd unit works with either the compose plugin or the
# standalone docker-compose binary from the fallback path.
cat > /usr/local/bin/n8n-compose << 'EOF'
#!/bin/sh
set -e
if command -v docker >/dev/null 2>&1 && docker compose version >/dev/null 2>&1; then
  exec docker compose "$@"
elif command -v docker-compose >/dev/null 2>&1; then
  exec docker-compose "$@"
fi
echo "docker compose or docker-compose not found" >&2
exit 1
EOF
chmod +x /usr/local/bin/n8n-compose

# -----------------------------------------------------------------------------
# n8n stack layout
# -----------------------------------------------------------------------------
echo "Preparing /opt/n8n..."
chmod +x /opt/n8n/n8n-init.sh /opt/n8n/update.sh

# n8n 2.0 restricts the file nodes to ~/.n8n-files; this is that directory,
# exposed on the host. 1000:1000 is the "node" user inside the n8n image.
mkdir -p /opt/n8n/files
chown 1000:1000 /opt/n8n/files

cat > /opt/n8n/.env.example << 'EOF'
# Reference copy of the configuration generated on first boot.
# The live file is /opt/n8n/.env; this one is never read.
N8N_IMAGE_TAG=latest
N8N_HOSTNAME=localhost
N8N_PROTOCOL=http
N8N_WEBHOOK_URL=http://localhost/
N8N_SECURE_COOKIE=false
GENERIC_TIMEZONE=UTC
N8N_ENCRYPTION_KEY=generated-on-first-boot
POSTGRES_PASSWORD=generated-on-first-boot
N8N_RUNNERS_AUTH_TOKEN=generated-on-first-boot
N8N_DIAGNOSTICS_ENABLED=false
N8N_LOG_LEVEL=info
N8N_UNVERIFIED_PACKAGES_ENABLED=true
N8N_RUNNERS_TASK_TIMEOUT=300
N8N_COMPRESSION_NODE_MAX_DECOMPRESSED_SIZE_BYTES=268435456
N8N_COMPRESSION_NODE_MAX_ZIP_ENTRIES=1000
EOF

echo "Validating Docker Compose definition..."
/usr/local/bin/n8n-compose --env-file /opt/n8n/.env.example -f /opt/n8n/docker-compose.yml config -q

# -----------------------------------------------------------------------------
# nginx reverse proxy
# -----------------------------------------------------------------------------
echo "Configuring nginx reverse proxy..."
install -m 0644 /opt/n8n/nginx.conf /etc/nginx/conf.d/n8n.conf
# Drop the Ubuntu default site so it cannot shadow the n8n vhost.
rm -f /etc/nginx/sites-enabled/default /etc/nginx/sites-available/default
nginx -t
systemctl enable nginx

# -----------------------------------------------------------------------------
# Pre-pull images so first boot does not wait on a download
# -----------------------------------------------------------------------------
echo "Pre-pulling container images..."
/usr/local/bin/n8n-compose --env-file /opt/n8n/.env.example -f /opt/n8n/docker-compose.yml pull

echo "Installed n8n version: $(docker run --rm --entrypoint n8n docker.io/n8nio/n8n:latest --version 2>/dev/null || echo 'unknown')"

# -----------------------------------------------------------------------------
# Services
# -----------------------------------------------------------------------------
# Enabled but not started: n8n-init.service writes /opt/n8n/.env on first boot,
# and n8n.service is ordered after it.
echo "Enabling services..."
chmod 0644 /etc/systemd/system/n8n.service /etc/systemd/system/n8n-init.service
systemctl daemon-reload
systemctl enable n8n-init.service
systemctl enable n8n.service

chmod +x /etc/update-motd.d/99-startup
chmod +x /var/lib/cloud/scripts/per-instance/001_onboot

apt-get -qqy clean

echo "n8n image build completed successfully!"
