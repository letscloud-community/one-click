#!/bin/bash
# Pulls the image tag configured in /opt/n8n/.env and restarts the stack.
#
# N8N_IMAGE_TAG defaults to "latest", which can cross a major version and
# introduce breaking changes. Pin an exact version in /opt/n8n/.env for
# predictable upgrades, and read the release notes before a major bump:
# https://docs.n8n.io/changelog/release-notes/

set -euo pipefail

cd /opt/n8n

TAG=$(sed -n 's/^N8N_IMAGE_TAG=//p' .env | tail -n1)
echo "Updating n8n to image tag '${TAG:-latest}'..."

/usr/local/bin/n8n-compose --env-file /opt/n8n/.env -f /opt/n8n/docker-compose.yml pull
systemctl restart n8n

echo "Pruning superseded images..."
docker image prune -f >/dev/null

echo
/usr/local/bin/n8n-compose --env-file /opt/n8n/.env -f /opt/n8n/docker-compose.yml ps
