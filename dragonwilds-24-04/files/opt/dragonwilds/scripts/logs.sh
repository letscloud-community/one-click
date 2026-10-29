#!/bin/bash
#
# Follows the RuneScape: Dragonwilds server logs.
#
#   logs.sh            follow the container output (SteamCMD + game)
#   logs.sh --game     follow RSDragonwilds.log written inside the world data
#   logs.sh --tail 200 show the last N lines and exit

set -euo pipefail

# shellcheck source=/opt/dragonwilds/scripts/common.sh
. /opt/dragonwilds/scripts/common.sh

dw_require_root
dw_load_env

MODE="container"
TAIL_LINES=""

while [ $# -gt 0 ]; do
  case "$1" in
    --game) MODE="game"; shift ;;
    --tail) TAIL_LINES="${2:-100}"; shift 2 ;;
    -h|--help)
      sed -n '2,8p' "$0" | sed 's/^# \{0,1\}//'
      exit 0 ;;
    *) echo "Unknown option: $1" >&2; exit 1 ;;
  esac
done

if [ "${MODE}" = "game" ]; then
  GAME_LOG="${DW_DATA_DIR}/${DW_GAMELOG_REL}"
  [ -f "${GAME_LOG}" ] || dw_die "${GAME_LOG} does not exist yet. The server may still be downloading."
  if [ -n "${TAIL_LINES}" ]; then
    tail -n "${TAIL_LINES}" "${GAME_LOG}"
  else
    echo "Following ${GAME_LOG} (Ctrl+C to exit)..."
    tail -n 100 -f "${GAME_LOG}"
  fi
  exit 0
fi

if [ -n "${TAIL_LINES}" ]; then
  dw_compose logs --tail "${TAIL_LINES}"
else
  echo "Following the container logs (Ctrl+C to exit)..."
  dw_compose logs -f --tail 100
fi
