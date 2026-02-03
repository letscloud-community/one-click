#!/bin/bash

set -e

echo "Updating system packages..."
apt-get update
apt-get upgrade -y

echo "Installing base dependencies..."
apt-get install -y ca-certificates curl gnupg lsb-release openssl

echo "Installing Node.js 22.x..."
curl -fsSL https://deb.nodesource.com/setup_22.x | bash -
apt-get install -y nodejs

echo "Installing OpenClaw CLI (skip onboarding for image build)..."
curl -fsSL https://openclaw.bot/install.sh | bash -s -- --no-onboard

echo "Installing Caddy for HTTPS..."
apt-get install -y debian-keyring debian-archive-keyring apt-transport-https
curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' | tee /etc/apt/sources.list.d/caddy-stable.list
apt-get update
apt-get install -y caddy
systemctl disable caddy

mkdir -p /opt/clawdbot /etc/caddy/ssl
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
systemctl status clawdbot --no-pager 2>/dev/null || true
echo ""
echo "=== Gateway Token ==="
if [ -f /opt/clawdbot/gateway-token.txt ]; then
  cat /opt/clawdbot/gateway-token.txt
else
  echo "Token not yet generated. Wait for first boot or run: openclaw onboard --install-daemon"
fi
echo ""
echo "=== Control UI Access ==="
if [ -f /opt/clawdbot/control-ui-url.txt ]; then
  echo "URL with token (copy and open in browser):"
  cat /opt/clawdbot/control-ui-url.txt
else
  myip=$(hostname -I | awk '{print$1}')
  token=$(cat /opt/clawdbot/gateway-token.txt 2>/dev/null || echo "")
  if [ -n "${token}" ]; then
    echo "https://${myip}/?token=${token}"
  fi
  echo "SSH tunnel: ssh -L 18789:localhost:18789 root@${myip}  then http://localhost:18789/"
fi
HELPEOF

cat > /opt/restart-openclaw.sh << 'HELPEOF'
#!/bin/bash
echo "Restarting OpenClaw Gateway..."
systemctl restart clawdbot
sleep 2
if systemctl is-active --quiet clawdbot; then
  echo "OpenClaw restarted successfully."
  myip=$(hostname -I | awk '{print$1}')
  echo "Control UI: ssh -L 18789:localhost:18789 root@${myip}  then http://localhost:18789/"
  echo "Logs: journalctl -u clawdbot -f"
else
  echo "Error: Failed to restart. Check: journalctl -u clawdbot -xe"
  exit 1
fi
HELPEOF

cat > /opt/update-openclaw.sh << 'HELPEOF'
#!/bin/bash
set -e
echo "Updating OpenClaw..."
systemctl stop clawdbot || true
openclaw update || true
systemctl start clawdbot
echo "Update completed. Run /opt/status-openclaw.sh to verify."
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
  cat > /etc/caddy/Caddyfile << CADDYEOF
${DOMAIN} {
    reverse_proxy localhost:18789
}
CADDYEOF
  echo ""
  echo "HTTPS enabled! Access: https://${DOMAIN}/"
  echo "Ensure DNS for ${DOMAIN} points to this server."
  TOKEN=$(cat /opt/clawdbot/gateway-token.txt 2>/dev/null || true)
  if [ -n "${TOKEN}" ]; then
    echo ""
    echo "URL with token (copy and open in browser):"
    echo "https://${DOMAIN}/?token=${TOKEN}"
    echo "https://${DOMAIN}/?token=${TOKEN}" > /opt/clawdbot/control-ui-url.txt
  fi
else
  SERVER_IP=$(hostname -I | awk '{print$1}')
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
  cat > /etc/caddy/Caddyfile << CADDYEOF
:443 {
    tls /etc/caddy/ssl/cert.pem /etc/caddy/ssl/key.pem
    reverse_proxy localhost:18789
}
CADDYEOF
  echo ""
  echo "HTTPS enabled! Access: https://${SERVER_IP}/"
  echo "Browser will show certificate warning - click Advanced -> Proceed."
  TOKEN=$(cat /opt/clawdbot/gateway-token.txt 2>/dev/null || true)
  if [ -n "${TOKEN}" ]; then
    echo ""
    echo "URL with token (copy and open in browser):"
    echo "https://${SERVER_IP}/?token=${TOKEN}"
    echo "https://${SERVER_IP}/?token=${TOKEN}" > /opt/clawdbot/control-ui-url.txt
  fi
fi

echo ""
echo "Token: cat /opt/clawdbot/gateway-token.txt"
echo "Port 443 must be open in firewall."
systemctl enable caddy
systemctl restart caddy
HELPEOF

chmod +x /opt/status-openclaw.sh /opt/restart-openclaw.sh /opt/update-openclaw.sh /opt/setup-https-openclaw.sh

chmod +x /var/lib/cloud/scripts/per-instance/001_clawdbot_boot
chmod +x /usr/local/bin/clawdbot-start
chmod +x /usr/local/bin/clawdbot-setup
chmod +x /etc/update-motd.d/99-startup

systemctl daemon-reload
systemctl enable clawdbot-setup
ln -sf /etc/systemd/system/clawdbot-setup.service \
  /etc/systemd/system/multi-user.target.wants/clawdbot-setup.service

echo "OpenClaw base setup completed. Token generated on first boot."
