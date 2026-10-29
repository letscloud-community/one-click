#!/bin/bash
#
# Coolify localhost activation script (non-interactive).
# Activates the SSH key so Coolify can manage the localhost server.

set -e

SSH_KEY_PATH="/data/coolify/ssh/keys/id.root@host.docker.internal"
COMPOSE_DIR="/data/coolify/source"

echo "=================================================="
echo "Coolify Localhost Server Activation"
echo "=================================================="
echo ""

# Make sure Coolify is running first.
if ! docker ps --format '{{.Names}}' | grep -q 'coolify'; then
  echo "Error: Coolify is not running."
  echo "Start it first with: systemctl start coolify"
  exit 1
fi

# Ensure the SSH key exists.
if [ ! -f "${SSH_KEY_PATH}" ]; then
  echo "SSH keys not found. Generating new keys..."
  mkdir -p "$(dirname "${SSH_KEY_PATH}")"
  ssh-keygen -f "${SSH_KEY_PATH}" -t ed25519 -N '' -C root@coolify -q
  chown -R 9999:root /data/coolify/ssh
  chmod -R 700 /data/coolify/ssh
  echo "  SSH keys generated."
else
  echo "  SSH keys found at ${SSH_KEY_PATH}"
fi
echo ""

# Skip if already activated.
if grep -q "root@coolify" /root/.ssh/authorized_keys 2>/dev/null; then
  echo "Localhost is already activated."
  echo "You can now use Coolify to deploy applications on this server."
  exit 0
fi

echo "Activating localhost access..."
mkdir -p /root/.ssh
chmod 700 /root/.ssh
cat "${SSH_KEY_PATH}.pub" >> /root/.ssh/authorized_keys
chmod 600 /root/.ssh/authorized_keys
echo "  SSH key added to authorized_keys."
echo ""

echo "Restarting Coolify to apply changes..."
cd "${COMPOSE_DIR}"
docker compose --env-file "${COMPOSE_DIR}/.env" \
  -f "${COMPOSE_DIR}/docker-compose.yml" \
  -f "${COMPOSE_DIR}/docker-compose.prod.yml" \
  restart
echo "  Coolify restarted."
echo ""

echo "=================================================="
echo "Localhost Activation Complete!"
echo "=================================================="
echo ""
echo "Next steps:"
echo "  1. Go to http://$(hostname -I | awk '{print $1}'):8000"
echo "  2. Open 'Servers' in the sidebar."
echo "  3. The localhost server should now show as connected."
echo ""
