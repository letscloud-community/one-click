#!/bin/bash
# Generates the per-instance n8n configuration and secrets.
#
# Runs once, from n8n-init.service, before n8n.service starts. The snapshot
# ships without any secrets so that every deployed instance gets its own
# credential encryption key and database password.

set -euo pipefail

ENV_FILE=/opt/n8n/.env
CRED_FILE=/root/.n8n_credentials

if [ -f "$ENV_FILE" ]; then
    echo "n8n-init: $ENV_FILE already exists, nothing to do."
    exit 0
fi

detect_ip() {
    local ip
    ip=$(ip -4 -o addr show scope global 2>/dev/null | awk '{print $4}' | cut -d/ -f1 | head -n1)
    case "${ip:-}" in
        ""|10.*|192.168.*|172.1[6-9].*|172.2[0-9].*|172.3[01].*|100.6[4-9].*|100.[7-9][0-9].*|100.1[01][0-9].*|100.12[0-7].*)
            ip=$(curl -fsS --max-time 10 https://api.ipify.org 2>/dev/null || true)
            ;;
    esac
    if [ -z "${ip:-}" ]; then
        ip=$(hostname -I 2>/dev/null | awk '{print $1}')
    fi
    printf '%s' "${ip:-localhost}"
}

ensure_swap() {
    # n8n, Postgres and the task runner together are tight on the smaller
    # plans; a small swapfile avoids the OOM killer during workflow bursts.
    local mem_kb
    mem_kb=$(awk '/^MemTotal:/{print $2}' /proc/meminfo)
    if [ "$(awk 'NR>1{s+=$3} END{print s+0}' /proc/swaps)" -gt 0 ] || [ "$mem_kb" -ge 4000000 ]; then
        return 0
    fi
    echo "n8n-init: creating 1G swapfile..."
    if fallocate -l 1G /swapfile 2>/dev/null || dd if=/dev/zero of=/swapfile bs=1M count=1024 status=none; then
        chmod 600 /swapfile
        mkswap /swapfile >/dev/null
        swapon /swapfile
        grep -q '^/swapfile ' /etc/fstab || echo '/swapfile none swap sw 0 0' >> /etc/fstab
        sysctl -q -w vm.swappiness=10
        echo 'vm.swappiness=10' > /etc/sysctl.d/99-n8n-swappiness.conf
    fi
}

SERVER_IP=$(detect_ip)
TIMEZONE=$(timedatectl show -p Timezone --value 2>/dev/null || true)
: "${TIMEZONE:=UTC}"

POSTGRES_PASSWORD=$(openssl rand -hex 24)
N8N_ENCRYPTION_KEY=$(openssl rand -hex 32)
N8N_RUNNERS_AUTH_TOKEN=$(openssl rand -hex 32)

umask 077
cat > "$ENV_FILE" << EOF
# n8n instance configuration - generated on first boot.
# Restart after editing:  systemctl restart n8n

# Image tag for both the n8n and the task runner images. They must always
# match. Pin an exact version (for example 2.45.4) to avoid unplanned major
# upgrades when running /opt/n8n/update.sh.
N8N_IMAGE_TAG=latest

# Public hostname and URL. Replace the IP with your domain once DNS points
# here, and switch N8N_PROTOCOL/N8N_SECURE_COOKIE after enabling HTTPS.
N8N_HOSTNAME=${SERVER_IP}
N8N_PROTOCOL=http
N8N_WEBHOOK_URL=http://${SERVER_IP}/
N8N_SECURE_COOKIE=false

# Timezone used by Schedule/Cron nodes.
GENERIC_TIMEZONE=${TIMEZONE}

# Secrets. N8N_ENCRYPTION_KEY decrypts every stored credential: back it up and
# never change it on an instance that already holds credentials.
N8N_ENCRYPTION_KEY=${N8N_ENCRYPTION_KEY}
POSTGRES_PASSWORD=${POSTGRES_PASSWORD}
N8N_RUNNERS_AUTH_TOKEN=${N8N_RUNNERS_AUTH_TOKEN}

N8N_DIAGNOSTICS_ENABLED=false
N8N_LOG_LEVEL=info

# n8n announced that the defaults below will change in a future release. They
# are pinned here so an upgrade never silently alters instance behaviour.
# Set to false to only allow verified community nodes.
N8N_UNVERIFIED_PACKAGES_ENABLED=true
# Seconds a Code node may run before the task runner restarts it.
N8N_RUNNERS_TASK_TIMEOUT=300
# Compression node limits, sized for the smaller plans (256 MiB / 1000 entries).
N8N_COMPRESSION_NODE_MAX_DECOMPRESSED_SIZE_BYTES=268435456
N8N_COMPRESSION_NODE_MAX_ZIP_ENTRIES=1000
EOF
chmod 600 "$ENV_FILE"

cat > "$CRED_FILE" << EOF
# n8n instance credentials - generated on first boot.
n8n_url="http://${SERVER_IP}/"
n8n_encryption_key="${N8N_ENCRYPTION_KEY}"
postgres_user="n8n"
postgres_database="n8n"
postgres_password="${POSTGRES_PASSWORD}"
runners_auth_token="${N8N_RUNNERS_AUTH_TOKEN}"
EOF
chmod 600 "$CRED_FILE"

# Swap is a nice-to-have; never fail initialization over it.
ensure_swap || echo "n8n-init: warning, could not configure swap." >&2

echo "n8n-init: configuration written to $ENV_FILE (server IP ${SERVER_IP})."
