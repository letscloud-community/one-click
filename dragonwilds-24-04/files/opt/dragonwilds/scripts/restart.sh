#!/bin/bash
#
# Restarts the RuneScape: Dragonwilds dedicated server and applies any change
# made to /opt/dragonwilds/.env.
#
# The container rebuilds DedicatedServer.ini from the environment on every
# start, so the container is recreated rather than merely restarted: a plain
# `docker compose restart` would reuse the old environment.
#
# Editing the .ini inside data/ while the server runs has no effect, because
# the file is regenerated at startup and the running server never re-reads it.

set -euo pipefail

# shellcheck source=/opt/dragonwilds/scripts/common.sh
. /opt/dragonwilds/scripts/common.sh

dw_require_root
dw_load_env

if [ -z "${RSDW_OWNER_ID:-}" ]; then
  dw_die "RSDW_OWNER_ID is empty in ${DW_ENV_FILE}. Run ${DW_SCRIPT_DIR}/first-boot.sh."
fi

dw_log INFO "Restarting the server to apply the current configuration..."
dw_fix_permissions
dw_compose up -d --force-recreate --remove-orphans

for _ in $(seq 1 30); do
  dw_container_running && break
  sleep 2
done

if dw_container_running; then
  dw_log INFO "Server restarted."
  dw_log INFO "Follow the startup with: ${DW_SCRIPT_DIR}/logs.sh"
else
  dw_log ERROR "The server did not come back. Last 40 log lines:"
  dw_compose logs --tail 40 || true
  exit 1
fi
