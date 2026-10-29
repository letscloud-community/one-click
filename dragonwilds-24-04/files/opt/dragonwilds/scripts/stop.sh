#!/bin/bash
#
# Stops the RuneScape: Dragonwilds dedicated server.
#
# Uses `docker compose stop`, which sends SIGTERM and waits for the
# stop_grace_period declared in docker-compose.yml (120s) so the server has
# time to flush the world to disk. Never kill the container outright: a save
# interrupted halfway can corrupt the world.

set -euo pipefail

# shellcheck source=/opt/dragonwilds/scripts/common.sh
. /opt/dragonwilds/scripts/common.sh

dw_require_root
dw_load_env

if ! dw_container_running; then
  dw_log INFO "The server is already stopped."
  exit 0
fi

dw_log INFO "Stopping the server and waiting for the final save (up to 120s)..."
dw_compose stop

if dw_container_running; then
  dw_log ERROR "The container is still running."
  exit 1
fi

dw_log INFO "Server stopped."
