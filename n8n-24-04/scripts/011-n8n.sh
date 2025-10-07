#!/bin/bash

# n8n Installation Script for Ubuntu 24.04
# This script installs n8n with Docker, PostgreSQL, and nginx reverse proxy

set -e

# Update system
echo "Updating system packages..."
apt-get update
apt-get upgrade -y

# Install Node.js 20.x (LTS) - required for n8n
echo "Installing Node.js 20.x..."
curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
apt-get install -y nodejs

# Verify Node.js version
echo "Node.js version: $(node --version)"
echo "npm version: $(npm --version)"

# Install PostgreSQL (host service)
echo "Installing PostgreSQL..."
apt-get install -y postgresql postgresql-contrib

# Configure PostgreSQL
echo "Configuring PostgreSQL..."
sudo -u postgres psql -c "CREATE USER n8n WITH PASSWORD 'n8n_password';"
sudo -u postgres psql -c "CREATE DATABASE n8n OWNER n8n;"
sudo -u postgres psql -c "GRANT ALL PRIVILEGES ON DATABASE n8n TO n8n;"

# Install nginx and Docker
echo "Installing nginx and Docker..."
apt-get install -y nginx ca-certificates curl gnupg lsb-release

# Try Docker official repository (preferred)
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

# Fallback to Ubuntu docker.io if official repo failed
if [ "$DOCKER_SETUP_OK" -ne 1 ]; then
  echo "Docker CE repo install failed; falling back to docker.io"
  apt-get install -y docker.io || true
fi
set -e

systemctl enable --now docker || true

# Provide a compose wrapper that uses either 'docker compose' or 'docker-compose'
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

# Prepare Docker Compose deployment for n8n
echo "Preparing Docker Compose for n8n..."
mkdir -p /opt/n8n
mkdir -p /opt/n8n/local-files

# Create n8n user
echo "Creating n8n user..."
useradd -m -s /bin/bash n8n

echo "Preparing n8n environment file..."
mkdir -p /home/n8n/.n8n
cat > /home/n8n/.n8n/.env << EOF
NODE_ENV=production
N8N_BASIC_AUTH_ACTIVE=true
N8N_BASIC_AUTH_USER=admin
N8N_BASIC_AUTH_PASSWORD=letscloud_change_password
DB_TYPE=postgresdb
DB_POSTGRESDB_HOST=localhost
DB_POSTGRESDB_PORT=5432
DB_POSTGRESDB_DATABASE=n8n
DB_POSTGRESDB_USER=n8n
DB_POSTGRESDB_PASSWORD=n8n_password
N8N_HOST=0.0.0.0
N8N_PORT=5678
N8N_PROTOCOL=http
WEBHOOK_URL=http://localhost/
N8N_LOG_LEVEL=info
N8N_LOG_OUTPUT=console
N8N_METRICS=true
N8N_SECURE_COOKIE=false
EOF

# Create Docker Compose file (working configuration with host networking)
cat > /opt/n8n/docker-compose.yml << 'EOF'
services:
  n8n:
    image: docker.n8n.io/n8nio/n8n
    restart: always
    network_mode: host
    environment:
      - N8N_ENFORCE_SETTINGS_FILE_PERMISSIONS=true
      - N8N_HOST=0.0.0.0
      - N8N_PORT=5678
      - N8N_PROTOCOL=http
      - N8N_RUNNERS_ENABLED=true
      - NODE_ENV=production
      - WEBHOOK_URL=http://localhost/
      - DB_TYPE=postgresdb
      - DB_POSTGRESDB_HOST=localhost
      - DB_POSTGRESDB_PORT=5432
      - DB_POSTGRESDB_DATABASE=n8n
      - DB_POSTGRESDB_USER=n8n
      - DB_POSTGRESDB_PASSWORD=n8n_password
      - N8N_LOG_LEVEL=info
      - N8N_LOG_OUTPUT=console
      - N8N_METRICS=true
      - N8N_SECURE_COOKIE=false
    volumes:
      - n8n_data:/home/node/.n8n
      - /opt/n8n/local-files:/files

volumes:
  n8n_data:
EOF

# Create systemd unit to manage n8n via Docker Compose
echo "Creating n8n systemd service (Docker Compose)..."
cat > /etc/systemd/system/n8n.service << 'EOF'
[Unit]
Description=n8n (Docker Compose)
After=network-online.target docker.service
Wants=docker.service

[Service]
Type=oneshot
RemainAfterExit=yes
WorkingDirectory=/opt/n8n
ExecStart=/usr/local/bin/n8n-compose -f /opt/n8n/docker-compose.yml up -d
ExecStop=/usr/local/bin/n8n-compose -f /opt/n8n/docker-compose.yml down
TimeoutStartSec=120

[Install]
WantedBy=multi-user.target
EOF

# Create nginx configuration for n8n (conf.d style)
echo "Configuring nginx reverse proxy..."
cat > /etc/nginx/conf.d/n8n.conf << 'EOF'
upstream n8n {
   server 127.0.0.1:5678;
}

server {
   listen 80 default_server;
   server_name _;

   access_log /var/log/nginx/n8n.access.log;
   error_log /var/log/nginx/n8n.error.log;

   location / {
        proxy_pass http://n8n;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;

        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
    }
}
EOF

# Remove Ubuntu default site to avoid welcome page taking precedence
rm -f /etc/nginx/sites-enabled/default /etc/nginx/sites-available/default 2>/dev/null || true

# Test nginx configuration
nginx -t

# Start and enable services
systemctl daemon-reload
systemctl enable postgresql
systemctl start postgresql
sleep 5

systemctl enable nginx
systemctl start nginx
sleep 2

# Ensure ownership and start Docker Compose-based n8n
mkdir -p /opt/n8n/data
chown -R n8n:n8n /home/n8n /opt/n8n
systemctl enable n8n
systemctl start n8n

# Install additional useful packages
echo "Installing additional packages..."
apt-get install -y curl wget git unzip

# Welcome message is now handled by /etc/update-motd.d/99-startup

echo "n8n installation completed successfully!"
echo "Complete the initial setup wizard to create your admin account!"
