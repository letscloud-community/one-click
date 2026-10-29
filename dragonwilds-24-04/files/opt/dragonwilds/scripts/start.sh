#!/bin/bash
#
# Starts the RuneScape: Dragonwilds dedicated server.

set -euo pipefail

# shellcheck source=/opt/dragonwilds/scripts/common.sh
. /opt/dragonwilds/scripts/common.sh

dw_require_root
dw_load_env

if [ -z "${RSDW_OWNER_ID:-}" ]; then
  dw_die "RSDW_OWNER_ID is empty in ${DW_ENV_FILE}. Run ${DW_SCRIPT_DIR}/first-boot.sh."
fi

dw_log INFO "Starting the dedicated server..."
dw_fix_permissions
dw_compose up -d --remove-orphans

if dw_container_running; then
  dw_log INFO "Container is up. SteamCMD checks for updates before the game starts."
  dw_log INFO "Follow the startup with: ${DW_SCRIPT_DIR}/logs.sh"
else
  dw_log ERROR "The container is not running. Last 40 log lines:"
  dw_compose logs --tail 40 || true
  exit 1
fi
