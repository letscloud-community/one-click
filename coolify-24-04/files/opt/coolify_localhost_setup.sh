#!/bin/bash
#
# Coolify localhost activation wizard.
#
# Runs interactively on the first SSH login and offers to activate the
# localhost server so Coolify can deploy applications on this machine.

set -e

MARKER="/root/.coolify_localhost_configured"
SSH_KEY_PATH="/data/coolify/ssh/keys/id.root@host.docker.internal"
COMPOSE_DIR="/data/coolify/source"

# If already configured, clean up .bashrc and exit so we never nag again.
if [ -f "${MARKER}" ]; then
  sed -i '/coolify_localhost_setup.sh/d' /root/.bashrc 2>/dev/null || true
  exit 0
fi

clear

cat << "EOF"
================================================================================
                       Coolify Localhost Setup
================================================================================

Welcome to your Coolify server!

Coolify is installed and running, but the localhost server needs to be
activated before you can deploy applications directly onto this machine.

Note: deploying to localhost is convenient for testing, but for production
you may prefer adding dedicated remote servers to avoid resource contention.

This setup will:
  - Activate the SSH key for localhost access
  - Restart Coolify to apply the change
  - Let you deploy applications immediately

EOF

read -rp "Would you like to activate localhost now? (recommended) [Y/n]: " REPLY
echo ""

if [[ ! "${REPLY}" =~ ^[Nn]$ ]]; then
  echo "Activating localhost server..."
  echo ""

  if [ ! -f "${SSH_KEY_PATH}" ]; then
    echo "Generating SSH keys..."
    mkdir -p "$(dirname "${SSH_KEY_PATH}")"
    ssh-keygen -f "${SSH_KEY_PATH}" -t ed25519 -N '' -C root@coolify -q
    chown -R 9999:root /data/coolify/ssh
    chmod -R 700 /data/coolify/ssh
  fi

  echo "Adding the public key to authorized_keys..."
  mkdir -p /root/.ssh
  chmod 700 /root/.ssh
  if ! grep -q "root@coolify" /root/.ssh/authorized_keys 2>/dev/null; then
    cat "${SSH_KEY_PATH}.pub" >> /root/.ssh/authorized_keys
  fi
  chmod 600 /root/.ssh/authorized_keys
  echo "  Done."
  echo ""

  sleep 2

  echo "Restarting Coolify (this may take 30-60 seconds)..."
  cd "${COMPOSE_DIR}"
  docker compose --env-file "${COMPOSE_DIR}/.env" \
    -f "${COMPOSE_DIR}/docker-compose.yml" \
    -f "${COMPOSE_DIR}/docker-compose.prod.yml" \
    up -d --pull always --remove-orphans
  echo "  Coolify restarted."
  echo ""

  touch "${MARKER}"
  MYIP="$(hostname -I | awk '{print $1}')"

  cat << EOF
================================================================================
                    Localhost Activation Complete!
================================================================================

Your Coolify instance is ready to deploy applications.

Access Coolify at: http://${MYIP}:8000

Next steps:
  1. Log in to Coolify (or create your admin account if you have not yet).
  2. Open "Servers" in the sidebar; localhost should show as connected.
  3. Create your first project and start deploying!

For help, visit: https://coolify.io/docs
================================================================================
EOF
else
  echo "Localhost activation skipped."
  echo ""
  echo "You can activate localhost later by running:"
  echo "  /opt/configure-coolify-localhost.sh"
  echo ""
  touch "${MARKER}"
fi

# Remove the wizard from .bashrc so it runs only once.
sed -i '/coolify_localhost_setup.sh/d' /root/.bashrc 2>/dev/null || true

echo ""
read -rp "Press ENTER to continue..." _
clear
