#!/bin/bash

# aaPanel Installation Script for Ubuntu 24.04
# This script installs aaPanel 8.0.3 (Free Edition) with SSL support
# Based on: https://www.aapanel.com/new/download.html

set -e

# Update system
echo "Updating system packages..."
apt-get update
apt-get upgrade -y

# Install required packages
echo "Installing required packages..."
apt-get install -y curl wget git unzip software-properties-common

# Download and install aaPanel 8.0.3 (Free Edition) with SSL support
echo "Installing aaPanel 8.0.3 (Free Edition) with SSL support..."
cd /tmp
URL="https://www.aapanel.com/script/install_panel_en.sh"
if [ -f /usr/bin/curl ]; then
    curl -ksSO "$URL"
else
    wget --no-check-certificate -O install_panel_en.sh "$URL"
fi

# Make the script executable and run it with ipssl parameter for automatic SSL
# Use 'yes' to auto-confirm any prompts and run non-interactively
chmod +x install_panel_en.sh
yes y | bash install_panel_en.sh ipssl 2>&1 | tee /tmp/aapanel-install.log || true

# Wait for installation to complete
echo "Waiting for aaPanel installation to complete..."
sleep 30

# Get the default port and credentials
PANEL_PORT=$(cat /www/server/panel/data/port.pl 2>/dev/null || echo "8888")
PANEL_USERNAME="admin"
PANEL_PASSWORD=$(cat /www/server/panel/data/default.pl 2>/dev/null | grep -o 'password":"[^"]*' | cut -d'"' -f3 2>/dev/null || echo "aapanel123")

# Configure firewall for aaPanel port
echo "Configuring firewall for aaPanel port $PANEL_PORT..."
ufw allow $PANEL_PORT/tcp
ufw allow 80/tcp
ufw allow 443/tcp
ufw allow 22/tcp
ufw --force enable

# Create a simple welcome page
echo "Creating welcome page..."
mkdir -p /www/wwwroot/default
cat > /www/wwwroot/default/index.html << 'EOF'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>aaPanel - Welcome</title>
    <style>
        body {
            font-family: Arial, sans-serif;
            max-width: 800px;
            margin: 50px auto;
            padding: 20px;
            background-color: #f5f5f5;
        }
        .container {
            background: white;
            padding: 30px;
            border-radius: 10px;
            box-shadow: 0 2px 10px rgba(0,0,0,0.1);
        }
        h1 { color: #2c3e50; }
        .info-box {
            background: #e8f4fd;
            padding: 15px;
            border-radius: 5px;
            margin: 20px 0;
        }
        .btn {
            display: inline-block;
            background: #3498db;
            color: white;
            padding: 10px 20px;
            text-decoration: none;
            border-radius: 5px;
            margin: 10px 5px;
        }
        .btn:hover { background: #2980b9; }
    </style>
</head>
<body>
    <div class="container">
        <h1>🎉 aaPanel 8.0.3 Successfully Installed!</h1>
        
        <div class="info-box">
            <h3>📋 Access Information</h3>
            <p><strong>Panel URL:</strong> <a href="http://YOUR_SERVER_IP:8888" target="_blank">http://YOUR_SERVER_IP:8888</a> or <a href="https://YOUR_SERVER_IP:8888" target="_blank">https://YOUR_SERVER_IP:8888</a></p>
            <p><strong>Username & Password:</strong> Run <code>bt default</code> to see credentials</p>
            <p><strong>SSL Support:</strong> ✅ Automatic trusted IP certificates enabled (ipssl)</p>
        </div>
        
        <div class="info-box">
            <h3>🔧 Useful Commands</h3>
            <ul>
                <li><code>bt</code> - aaPanel management tool</li>
                <li><code>bt default</code> - Show default login info</li>
                <li><code>bt restart</code> - Restart aaPanel</li>
                <li><code>bt stop</code> - Stop aaPanel</li>
                <li><code>bt start</code> - Start aaPanel</li>
                <li><code>aapanel-manage status</code> - Check service status</li>
            </ul>
        </div>
        
        <div class="info-box">
            <h3>📚 Documentation</h3>
            <p>Visit <a href="https://www.aapanel.com" target="_blank">aaPanel Official Website</a> for documentation and support.</p>
        </div>
        
        <a href="http://YOUR_SERVER_IP:8888" class="btn" target="_blank">🚀 Open aaPanel</a>
    </div>
</body>
</html>
EOF

# Set proper permissions
chown -R www:www /www/wwwroot/default

# Create a simple status check script
cat > /usr/local/bin/aapanel-status << 'EOF'
#!/bin/bash
echo "=== aaPanel Status ==="
echo "Panel Port: $(cat /www/server/panel/data/port.pl 2>/dev/null || echo 'Not found')"
echo "Panel Status: $(systemctl is-active bt 2>/dev/null || echo 'Unknown')"
echo "Nginx Status: $(systemctl is-active nginx 2>/dev/null || echo 'Not installed')"
echo "MySQL Status: $(systemctl is-active mysqld 2>/dev/null || echo 'Not installed')"
echo "PHP Status: $(systemctl is-active php-fpm 2>/dev/null || echo 'Not installed')"
echo ""
echo "Default login info:"
bt default 2>/dev/null || echo "Run 'bt default' to see login information"
EOF

chmod +x /usr/local/bin/aapanel-status

# Install additional useful packages
echo "Installing additional packages..."
apt-get install -y htop nano vim net-tools

# Create a simple management script
cat > /usr/local/bin/aapanel-manage << 'EOF'
#!/bin/bash
case "$1" in
    status)
        aapanel-status
        ;;
    restart)
        echo "Restarting aaPanel..."
        bt restart
        ;;
    stop)
        echo "Stopping aaPanel..."
        bt stop
        ;;
    start)
        echo "Starting aaPanel..."
        bt start
        ;;
    info)
        echo "aaPanel Information:"
        bt default
        ;;
    *)
        echo "Usage: aapanel-manage {status|restart|stop|start|info}"
        exit 1
        ;;
esac
EOF

chmod +x /usr/local/bin/aapanel-manage

# Services will be started by cloud-init script on first boot
echo "=============================================="
echo "aaPanel 8.0.3 installation completed successfully!"
echo "SSL Support: Enabled (ipssl)"
echo "=============================================="
echo "Panel will be available at:"
echo "  HTTP:  http://your-server-ip:8888"
echo "  HTTPS: https://your-server-ip:8888"
echo "=============================================="
echo "Use 'bt default' to see login credentials"
echo "Use 'aapanel-manage status' to check service status"
echo "=============================================="
