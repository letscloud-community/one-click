#!/bin/bash

set -e

echo "Updating system packages..."
apt-get update
apt-get upgrade -y

echo "Installing base dependencies..."
apt-get install -y ca-certificates curl gnupg lsb-release openssl

echo "Installing Node.js 24.x..."
curl -fsSL https://deb.nodesource.com/setup_24.x | bash -
apt-get install -y nodejs

echo "Installing OpenClaw CLI (skip onboarding for image build)..."
curl -fsSL --proto '=https' --tlsv1.2 https://openclaw.ai/install.sh | bash -s -- --no-onboard

echo "Installing Caddy for HTTPS..."
apt-get install -y debian-keyring debian-archive-keyring apt-transport-https
curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' | tee /etc/apt/sources.list.d/caddy-stable.list
apt-get update
apt-get install -y caddy
systemctl disable caddy

mkdir -p /opt/openclaw /etc/caddy/ssl
mkdir -p /etc/systemd/system/caddy.service.d
cat > /etc/systemd/system/caddy.service.d/override.conf << 'OVREOF'
[Service]
AmbientCapabilities=CAP_NET_BIND_SERVICE
CapabilityBoundingSet=CAP_NET_BIND_SERVICE CAP_NET_RAW
OVREOF

# Helper scripts
cat > /opt/status-openclaw.sh << 'HELPEOF'
#!/bin/bash
echo "=== OpenClaw Gateway Status ==="
systemctl status openclaw --no-pager 2>/dev/null || true
echo ""
echo "=== Gateway Token ==="
if [ -f /opt/openclaw/gateway-token.txt ]; then
  cat /opt/openclaw/gateway-token.txt
else
  echo "Token not yet generated. Wait for first boot or run: openclaw onboard --install-daemon"
fi
echo ""
echo "=== Control UI Access ==="
if [ -f /opt/openclaw/control-ui-url.txt ]; then
  echo "URL with token (copy and open in browser):"
  cat /opt/openclaw/control-ui-url.txt
else
  myip=$(hostname -I | awk '{print$1}')
  token=$(cat /opt/openclaw/gateway-token.txt 2>/dev/null || echo "")
  if [ -n "${token}" ]; then
    echo "https://${myip}/?token=${token}"
  fi
  echo "SSH tunnel: ssh -L 18789:localhost:18789 root@${myip}  then http://localhost:18789/"
fi
HELPEOF

cat > /opt/restart-openclaw.sh << 'HELPEOF'
#!/bin/bash
echo "Restarting OpenClaw Gateway..."
# Stop first and wait for the port to be released, otherwise the readiness
# probe can be answered by the process that is still shutting down.
systemctl stop openclaw
for _ in $(seq 1 60); do
  ss -lnt "sport = :18789" 2>/dev/null | grep -q 18789 || break
  sleep 1
done
systemctl start openclaw
echo "Waiting for the gateway to accept requests (this takes ~30s)..."
if systemctl is-active --quiet openclaw && /usr/local/bin/openclaw-wait-ready 300; then
  echo "OpenClaw restarted successfully."
  if [ -f /opt/openclaw/control-ui-url.txt ]; then
    echo "Control UI: $(cat /opt/openclaw/control-ui-url.txt)"
  fi
  echo "Logs: journalctl -u openclaw -f"
else
  echo "Error: Failed to restart. Check: journalctl -u openclaw -xe"
  exit 1
fi
HELPEOF

cat > /opt/update-openclaw.sh << 'HELPEOF'
#!/bin/bash
set -euo pipefail
echo "Updating OpenClaw..."
systemctl stop openclaw
if openclaw update; then
  systemctl start openclaw
  echo "Waiting for the gateway to accept requests (this takes ~30s)..."
  /usr/local/bin/openclaw-wait-ready 300 || echo "Warning: gateway not ready yet; check: journalctl -u openclaw -xe" >&2
  echo "Update completed. Run /opt/status-openclaw.sh to verify."
else
  update_status=$?
  echo "Error: OpenClaw update failed. Attempting to restart the Gateway." >&2
  if ! systemctl start openclaw; then
    echo "Error: Gateway restart failed. Check: journalctl -u openclaw -xe" >&2
  fi
  exit "${update_status}"
fi
HELPEOF

cat > /opt/setup-https-openclaw.sh << 'HELPEOF'
#!/bin/bash
# Enable HTTPS for OpenClaw Control UI via Caddy
# Usage: /opt/setup-https-openclaw.sh [domain]
#   No arg: self-signed cert for IP (port 443) - browser will show cert warning
#   Domain: Let's Encrypt (ports 80/443) - requires domain pointing to this server

set -e
DOMAIN="${1:-}"

if ! command -v caddy >/dev/null 2>&1; then
  echo "Installing Caddy..."
  apt-get update
  apt-get install -y debian-keyring debian-archive-keyring apt-transport-https curl
  curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
  curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' | tee /etc/apt/sources.list.d/caddy-stable.list
  apt-get update
  apt-get install -y caddy
fi
mkdir -p /etc/caddy /etc/caddy/ssl

if [ -n "${DOMAIN}" ]; then
  echo "Configuring Caddy for ${DOMAIN} (Let's Encrypt)..."
  /usr/local/bin/openclaw-write-caddyfile "${DOMAIN}"
  ACCESS_HOST="${DOMAIN}"
  echo ""
  echo "HTTPS enabled! Access: https://${DOMAIN}/"
  echo "Ensure DNS for ${DOMAIN} points to this server."
else
  SERVER_IP=$(curl -s --connect-timeout 2 https://ifconfig.me 2>/dev/null || curl -s --connect-timeout 2 https://api.ipify.org 2>/dev/null || hostname -I | awk '{print$1}')
  echo "Configuring Caddy with self-signed cert for ${SERVER_IP}..."
  openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
    -keyout /etc/caddy/ssl/key.pem -out /etc/caddy/ssl/cert.pem \
    -subj "/CN=${SERVER_IP}" -addext "subjectAltName=IP:${SERVER_IP}"
  chown caddy:caddy /etc/caddy/ssl/*.pem
  chmod 600 /etc/caddy/ssl/key.pem
  chmod 644 /etc/caddy/ssl/cert.pem
  mkdir -p /etc/systemd/system/caddy.service.d
  cat > /etc/systemd/system/caddy.service.d/override.conf << 'OVREOF'
[Service]
AmbientCapabilities=CAP_NET_BIND_SERVICE
CapabilityBoundingSet=CAP_NET_BIND_SERVICE CAP_NET_RAW
OVREOF
  systemctl daemon-reload
  /usr/local/bin/openclaw-write-caddyfile
  ACCESS_HOST="${SERVER_IP}"
  echo ""
  echo "HTTPS enabled! Access: https://${SERVER_IP}/"
  echo "Browser will show certificate warning - click Advanced -> Proceed."
fi

# Teach the gateway about the proxy and the new browser origin, otherwise it
# answers HTTP 403 proxy_attribution_required behind Caddy.
/usr/local/bin/openclaw-set-origin "https://${ACCESS_HOST}"
systemctl stop openclaw
for _ in $(seq 1 60); do
  ss -lnt "sport = :18789" 2>/dev/null | grep -q 18789 || break
  sleep 1
done
systemctl start openclaw

TOKEN=$(cat /opt/openclaw/gateway-token.txt 2>/dev/null || true)
if [ -n "${TOKEN}" ]; then
  echo ""
  echo "URL with token (copy and open in browser):"
  echo "https://${ACCESS_HOST}/?token=${TOKEN}"
  echo "https://${ACCESS_HOST}/?token=${TOKEN}" > /opt/openclaw/control-ui-url.txt
fi

echo ""
echo "Token: cat /opt/openclaw/gateway-token.txt"
echo "Port 443 must be open in firewall."
systemctl enable caddy
systemctl restart caddy
/usr/local/bin/openclaw-wait-ready 300 || echo "Warning: gateway not ready yet; check: journalctl -u openclaw -xe"
HELPEOF

chmod +x /opt/status-openclaw.sh /opt/restart-openclaw.sh /opt/update-openclaw.sh /opt/setup-https-openclaw.sh

chmod +x /var/lib/cloud/scripts/per-instance/001_openclaw_boot
chmod +x /usr/local/bin/openclaw-start
chmod +x /usr/local/bin/openclaw-setup
chmod +x /usr/local/bin/openclaw-set-origin
chmod +x /usr/local/bin/openclaw-write-caddyfile
chmod +x /usr/local/bin/openclaw-wait-ready
chmod +x /etc/update-motd.d/99-startup

systemctl daemon-reload
systemctl enable openclaw-setup
ln -sf /etc/systemd/system/openclaw-setup.service \
  /etc/systemd/system/multi-user.target.wants/openclaw-setup.service

echo "OpenClaw base setup completed. Token generated on first boot."
