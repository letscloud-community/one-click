#!/bin/sh

# Install Easypanel using official installer
echo "Installing Easypanel using official installer..."

# Install Easypanel
curl -sSL https://get.easypanel.io | sh

# Enable Docker to start on boot
systemctl enable docker

echo "Easypanel installation completed!"
