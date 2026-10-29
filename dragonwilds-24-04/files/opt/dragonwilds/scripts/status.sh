#!/bin/bash
#
# Overview of the RuneScape: Dragonwilds dedicated server:
# container state, connection details, worlds, backups and pending updates.

set -euo pipefail

# shellcheck source=/opt/dragonwilds/scripts/common.sh
. /opt/dragonwilds/scripts/common.sh

dw_require_root
dw_load_env

PORT="${RSDW_PORT:-7777}"
BEACON_PORT="${RSDW_BEACON_PORT:-8888}"
# -4 matters: the game port is published over IPv4 and an IPv6 answer would
# produce an address that players cannot use.
MYIP="$(curl -4 -fsSL --max-time 5 https://ifconfig.me 2>/dev/null \
  || curl -4 -fsSL --max-time 5 https://api.ipify.org 2>/dev/null \
  || hostname -I | awk '{print $1}')"

echo "================================================================================"
echo " RuneScape: Dragonwilds Dedicated Server"
echo "================================================================================"
echo ""

# --- Container ---------------------------------------------------------------

if dw_container_running; then
  since="$(docker inspect -f '{{.State.StartedAt}}' "${DW_CONTAINER}" 2>/dev/null | cut -c1-19 | tr 'T' ' ')"
  echo "  State          RUNNING (since ${since} UTC)"
else
  state="$(docker inspect -f '{{.State.Status}}' "${DW_CONTAINER}" 2>/dev/null || echo 'not created')"
  echo "  State          STOPPED (${state})"
fi

image="$(docker inspect -f '{{.Config.Image}}' "${DW_CONTAINER}" 2>/dev/null || echo '-')"
echo "  Image          ${image}"

build="$(dw_installed_build_id || echo 'not installed yet')"
echo "  Steam build    ${build}"
echo ""

# --- Connection --------------------------------------------------------------

echo "  World name     ${RSDW_WORLD_NAME:-<unset>}"
echo "                 (search for this exactly, it is case sensitive)"
# A name configured before the 16 character limit was enforced still works, but
# the browser only shows the first 16, so spell out what players must type.
if [ "${#RSDW_WORLD_NAME}" -gt "${DW_NAME_MAXLEN}" ]; then
  echo "                 !! ${#RSDW_WORLD_NAME} characters: the browser only shows"
  echo "                    \"${RSDW_WORLD_NAME:0:${DW_NAME_MAXLEN}}\", which is what players must search for"
fi
JOIN_CODE="$(dw_join_code)"
if [ -n "${JOIN_CODE}" ]; then
  echo "  Join code      ${JOIN_CODE}  (quickest way in, skips the search)"
else
  echo "  Join code      not published yet (the world is still loading)"
fi
if [ "${#RSDW_SERVER_NAME}" -gt "${DW_NAME_MAXLEN}" ]; then
  echo "  Server name    ${RSDW_SERVER_NAME} (shown as \"${RSDW_SERVER_NAME:0:${DW_NAME_MAXLEN}}\")"
else
  echo "  Server name    ${RSDW_SERVER_NAME:-<unset>}"
fi
echo "  Address        ${MYIP}:${PORT}/udp"
echo "  Beacon port    ${BEACON_PORT}/udp (required by the Worlds browser)"
echo "  Owner ID       ${RSDW_OWNER_ID:-<unset>}"
if [ -n "${RSDW_PASSWORD:-}" ]; then
  echo "  World password set (see ${DW_ENV_FILE})"
else
  echo "  World password none, the world is open"
fi
echo ""

# --- Players -----------------------------------------------------------------

if players="$(dw_player_count)"; then
  echo "  Connections    ${players} active on UDP/${PORT} (best effort)"
else
  echo "  Connections    unknown (conntrack unavailable)"
fi
echo ""

# --- Resources ---------------------------------------------------------------

if dw_container_running; then
  stats="$(docker stats --no-stream --format '{{.CPUPerc}} {{.MemUsage}}' "${DW_CONTAINER}" 2>/dev/null || true)"
  [ -n "${stats}" ] && echo "  CPU / memory   ${stats}"
fi

if [ -d "${DW_DATA_DIR}" ]; then
  echo "  Data size      $(du -sh "${DW_DATA_DIR}" 2>/dev/null | awk '{print $1}')"
fi
echo "  Disk free      $(df -h "${DW_DIR}" | tail -n1 | awk '{print $4" of "$2" ("$5" used)"}')"
echo "  System memory  $(free -h | awk '/^Mem:/ {print $3" used of "$2}')"
echo ""

# --- Worlds ------------------------------------------------------------------

echo "  Worlds in ${DW_SAVE_DIR}:"
if [ -n "$(find "${DW_SAVE_DIR}" -maxdepth 1 -name '*.sav' -print -quit 2>/dev/null)" ]; then
  find "${DW_SAVE_DIR}" -maxdepth 1 -name '*.sav' -printf '    %-42f %8s bytes  %Td/%Tm/%TY %TH:%TM\n' | sort
else
  echo "    (none yet; the server creates one on its first successful start)"
fi
echo ""

# --- Backups -----------------------------------------------------------------

echo "  Backups:"
for tier in hourly daily weekly manual pre-update pre-restore; do
  dir="${DW_BACKUP_DIR}/${tier}"
  [ -d "${dir}" ] || continue
  count="$(find "${dir}" -maxdepth 1 -name '*.tar.gz' | wc -l)"
  [ "${count}" -eq 0 ] && continue
  newest="$(find "${dir}" -maxdepth 1 -name '*.tar.gz' -printf '%T@ %p\n' | sort -rn | head -n1 | cut -d' ' -f2-)"
  printf '    %-12s %3s archive(s), newest %s\n' "${tier}" "${count}" "$(date -r "${newest}" +'%Y-%m-%d %H:%M')"
done
[ -d "${DW_BACKUP_DIR}" ] && echo "    total size   $(du -sh "${DW_BACKUP_DIR}" 2>/dev/null | awk '{print $1}')"
echo ""

# --- Timers ------------------------------------------------------------------

echo "  Timers:"
for unit in dragonwilds-backup.timer dragonwilds-update.timer; do
  if systemctl is-active --quiet "${unit}" 2>/dev/null; then
    next="$(systemctl show "${unit}" -p NextElapseUSecRealtime --value 2>/dev/null)"
    printf '    %-26s active (next: %s)\n' "${unit}" "${next:-unknown}"
  else
    printf '    %-26s inactive\n' "${unit}"
  fi
done
echo ""

# --- Pending update ----------------------------------------------------------

if [ -f "${DW_STATE_DIR}/update-pending" ]; then
  echo "  ** A game update is pending **"
  sed 's/^/    /' "${DW_STATE_DIR}/update-pending"
  echo "    Apply it with: ${DW_SCRIPT_DIR}/update.sh --now"
  echo ""
fi

# --- Firewall ----------------------------------------------------------------

if command -v ufw >/dev/null 2>&1; then
  echo "  Firewall (ufw):"
  ufw status 2>/dev/null | sed 's/^/    /' | head -n 12
  echo ""
fi

echo "================================================================================"
