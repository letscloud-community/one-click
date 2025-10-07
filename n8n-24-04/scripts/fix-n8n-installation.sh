#!/bin/bash

# Fix n8n installation script
# This script fixes corrupted n8n installation and updates Node.js

echo "Fixing n8n installation..."

# Stop n8n service
systemctl stop n8n

# Check Node.js version
NODE_VERSION=$(node --version 2>/dev/null | cut -d'v' -f2 | cut -d'.' -f1)
echo "Current Node.js version: $NODE_VERSION"

# Update Node.js to 20.x if needed
if [ "$NODE_VERSION" -lt 20 ]; then
    echo "Node.js version is too old for n8n. Updating to Node.js 20.x..."
    
    # Remove old Node.js
    apt-get remove -y nodejs npm
    rm -rf /usr/lib/node_modules
    rm -rf /usr/bin/node
    rm -rf /usr/bin/npm
    
    # Install Node.js 20.x
    curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
    apt-get install -y nodejs
    
    echo "Node.js updated to: $(node --version)"
fi

# Remove corrupted n8n installation
echo "Removing corrupted n8n installation..."
npm uninstall -g n8n 2>/dev/null || true
rm -rf /usr/lib/node_modules/n8n 2>/dev/null || true
rm -rf /usr/bin/n8n 2>/dev/null || true
rm -rf /root/.npm 2>/dev/null || true

# Clean npm cache
echo "Cleaning npm cache..."
npm cache clean --force

# Reinstall n8n with proper permissions
echo "Reinstalling n8n..."
npm install -g n8n@latest --unsafe-perm=true --allow-root

# Regenerate nginx config in conf.d style
echo "Regenerating nginx configuration..."
cat > /etc/nginx/conf.d/n8n.conf << 'EOF'
upstream n8n {
   server 127.0.0.1:5678;
}

server {
   listen 80;
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

# Reload nginx
nginx -t && systemctl reload nginx || systemctl restart nginx

# Verify installation
if [ -f /usr/bin/n8n ]; then
    echo "n8n installation successful!"
    chmod +x /usr/bin/n8n
    
    # Test n8n
    if /usr/bin/n8n --version > /dev/null 2>&1; then
        echo "n8n is working correctly!"
        
        # Restart services
        systemctl daemon-reload
        systemctl restart postgresql
        systemctl restart nginx
        systemctl restart n8n
        
        echo "Services restarted successfully!"
        echo "Check status with: systemctl status n8n"
    else
        echo "n8n installation verification failed!"
        exit 1
    fi
else
    echo "n8n installation failed!"
    exit 1
fi
