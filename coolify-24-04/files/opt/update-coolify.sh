#!/bin/bash

# Update Coolify to the latest version.
echo "Updating Coolify to the latest version..."

cd /data/coolify/source

# Download the latest upgrade script and run it.
curl -fsSL https://cdn.coollabs.io/coolify/upgrade.sh -o /data/coolify/source/upgrade.sh
chmod +x /data/coolify/source/upgrade.sh
bash /data/coolify/source/upgrade.sh

echo "Coolify updated successfully!"
