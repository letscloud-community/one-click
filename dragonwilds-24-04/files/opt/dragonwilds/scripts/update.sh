#!/bin/bash
#
# Controlled update of the RuneScape: Dragonwilds dedicated server.
#
# How updating actually works
# ---------------------------
# The official image runs `steamcmd +app_update 4019830` every time the
# container starts, so a restart IS the update. While running, it polls Valve's
# UpToDateCheck API every 30 minutes and, if RSDW_AUTO_STOP_ON_UPDATE=true,
# exits so the restart policy brings it back on the new build.
#
# That built-in behaviour is left disabled on purpose, because it drops players
# the instant Jagex ships a build. This script does the same job with guards:
#
#   1. ask Valve whether the installed build id is still current;
#   2. only act inside the configured maintenance window;
#   3. only act when no player is connected;
#   4. take a cold backup before touching anything;
#   5. pull the newest image and recreate the container, which triggers the
#      SteamCMD update on the way up;
#   6. verify the server came back, and log every step.
#
# The world lives in a bind mount that is never deleted, so the update replaces
# only the game binaries. Clients must run the same build as the server, so an
# outdated server simply disappears from the browser until it is updated.
#
# Usage:
#   update.sh --check     report whether an update is pending, change nothing
#   update.sh             apply the policy in DW_UPDATE_MODE (used by the timer)
#   update.sh --now       update immediately, ignoring window and idle checks
#   update.sh --force     alias for --now

set -euo pipefail

# shellcheck source=/opt/dragonwilds/scripts/common.sh
. /opt/dragonwilds/scripts/common.sh

CHECK_ONLY=0
FORCE=0

while [ $# -gt 0 ]; do
  case "$1" in
    --check)       CHECK_ONLY=1; shift ;;
    --now|--force) FORCE=1; shift ;;
    -h|--help)
      sed -n '2,34p' "$0" | sed 's/^# \{0,1\}//'
      exit 0 ;;
    *) echo "Unknown option: $1" >&2; exit 1 ;;
  esac
done

dw_require_root
dw_tee_log update
dw_load_env

PENDING_FLAG="${DW_STATE_DIR}/update-pending"
mkdir -p "${DW_STATE_DIR}"

MODE="${DW_UPDATE_MODE:-window}"
WINDOW_HOUR="${DW_UPDATE_WINDOW_HOUR:-5}"
REQUIRE_IDLE="${DW_UPDATE_REQUIRE_IDLE:-true}"

# Set when Steam cannot tell us whether a new build exists and SteamCMD has to
# decide during a restart instead.
FALLBACK_MODE=0
STAMP_FILE="${DW_STATE_DIR}/last-maintenance-restart"
MIN_INTERVAL=$(( ${DW_UPDATE_FALLBACK_DAYS:-1} * 86400 ))

# --- 1. Is there a new build? ------------------------------------------------

INSTALLED_BUILD="$(dw_installed_build_id || true)"

if [ -z "${INSTALLED_BUILD}" ]; then
  dw_log WARN "No Steam app manifest yet; the first download is probably still running."
  exit 0
fi

dw_log INFO "Installed Steam build id: ${INSTALLED_BUILD}"

RESPONSE="$(curl -fsS --max-time 30 --get "${DW_STEAM_UPTODATE_API}" \
  --data-urlencode "appid=${DW_STEAM_APPID}" \
  --data-urlencode "version=${INSTALLED_BUILD}" \
  --data-urlencode "format=json" 2>/dev/null || true)"

if [ -z "${RESPONSE}" ]; then
  dw_log WARN "Could not reach the Steam UpToDateCheck API; will try again on the next run."
  exit 0
fi

SUCCESS="$(printf '%s' "${RESPONSE}" | jq -r '.response.success // empty')"
UP_TO_DATE="$(printf '%s' "${RESPONSE}" | jq -r '.response.up_to_date // empty')"
REQUIRED_VERSION="$(printf '%s' "${RESPONSE}" | jq -r '.response.required_version // empty')"

if [ "${SUCCESS}" != "true" ]; then
  # Valve does not publish app info for every dedicated server tool, and at the
  # time of writing appid 4019830 answers with
  # "Couldn't get app info for the app specified.". The official image hits the
  # same wall and simply keeps running, which would mean updates are never
  # applied. The fallback below asks SteamCMD instead: recreating the container
  # runs `app_update`, which is a no-op when the build is already current.
  API_ERROR="$(printf '%s' "${RESPONSE}" | jq -r '.response.error // "unknown"')"
  dw_log WARN "Steam UpToDateCheck is unavailable for appid ${DW_STEAM_APPID}: ${API_ERROR}"

  if [ "${DW_UPDATE_FALLBACK:-true}" != "true" ]; then
    dw_log INFO "DW_UPDATE_FALLBACK is disabled; nothing to do."
    exit 0
  fi

  if [ "${CHECK_ONLY}" -eq 1 ]; then
    echo ""
    echo "Steam cannot confirm the version of this build."
    echo "Let SteamCMD decide with: ${DW_SCRIPT_DIR}/update.sh --now"
    exit 0
  fi

  # Without the API there is no way to know an update is waiting, so the
  # maintenance restart is rate limited instead of running every hour. The
  # stamp is only consumed once the run actually reaches the restart.
  FALLBACK_MODE=1
  REQUIRED_VERSION="unknown"

  if [ "${FORCE}" -eq 0 ] && [ -f "${STAMP_FILE}" ]; then
    last="$(cat "${STAMP_FILE}" 2>/dev/null || echo 0)"
    age=$(( $(date +%s) - last ))
    if [ "${age}" -lt "${MIN_INTERVAL}" ]; then
      dw_log INFO "Last maintenance restart was $(( age / 3600 ))h ago; waiting for the $(( MIN_INTERVAL / 3600 ))h interval."
      exit 0
    fi
  fi

  dw_log INFO "Eligible for a maintenance restart so SteamCMD can apply any pending build."
elif [ "${UP_TO_DATE}" = "true" ]; then
  dw_log INFO "The server is up to date."
  rm -f "${PENDING_FLAG}"
  exit 0
fi

if [ "${FALLBACK_MODE}" -eq 0 ]; then
  dw_log INFO "An update is available: installed=${INSTALLED_BUILD}, required=${REQUIRED_VERSION}"
  printf 'installed=%s\nrequired=%s\ndetected=%s\n' \
    "${INSTALLED_BUILD}" "${REQUIRED_VERSION}" "$(date -u +'%Y-%m-%dT%H:%M:%SZ')" > "${PENDING_FLAG}"

  if [ "${CHECK_ONLY}" -eq 1 ]; then
    echo ""
    echo "An update is pending. Apply it with: ${DW_SCRIPT_DIR}/update.sh --now"
    exit 0
  fi
fi

# --- 2. Policy gate ----------------------------------------------------------

if [ "${FORCE}" -eq 0 ]; then
  case "${MODE}" in
    notify)
      dw_log INFO "DW_UPDATE_MODE=notify, so nothing is restarted automatically."
      dw_log INFO "Apply it whenever you like with: ${DW_SCRIPT_DIR}/update.sh --now"
      exit 0
      ;;
    window)
      current_hour="$(date +%-H)"
      if [ "${current_hour}" -ne "${WINDOW_HOUR}" ]; then
        dw_log INFO "Outside the maintenance window (now ${current_hour}h, window ${WINDOW_HOUR}h). Deferring."
        exit 0
      fi
      dw_log INFO "Inside the maintenance window (${WINDOW_HOUR}h)."
      ;;
    immediate)
      dw_log INFO "DW_UPDATE_MODE=immediate."
      ;;
    *)
      dw_log WARN "Unknown DW_UPDATE_MODE \"${MODE}\"; treating it as notify."
      exit 0
      ;;
  esac
fi

# --- 3. Do not interrupt an active session -----------------------------------

if [ "${REQUIRE_IDLE}" = "true" ] && [ "${FORCE}" -eq 0 ]; then
  if PLAYERS="$(dw_player_count)"; then
    if [ "${PLAYERS}" -gt 0 ]; then
      dw_log INFO "${PLAYERS} connection(s) still active on UDP/${RSDW_PORT:-7777}. Deferring to protect the session."
      exit 0
    fi
    dw_log INFO "No active connections detected."
  else
    dw_log WARN "Cannot determine whether players are connected (conntrack unavailable)."
    dw_log WARN "Proceeding, because the maintenance window already limits the impact."
  fi
fi

# --- 4. Cold backup before changing anything ---------------------------------

# Every gate has been cleared, so record the attempt before doing any work.
[ "${FALLBACK_MODE}" -eq 1 ] && date +%s > "${STAMP_FILE}"

dw_log INFO "Taking a cold backup before updating..."
if ! "${DW_SCRIPT_DIR}/backup.sh" --tier pre-update --cold --label "build-${INSTALLED_BUILD}"; then
  dw_die "The pre-update backup failed. Aborting without updating."
fi

# --- 5. Pull and recreate ----------------------------------------------------

dw_log INFO "Pulling the latest official image..."
dw_compose pull || dw_log WARN "Image pull failed; continuing with the local image."

dw_log INFO "Recreating the container, which makes SteamCMD fetch the new build..."
dw_compose up -d --force-recreate

# --- 6. Verify ---------------------------------------------------------------

dw_log INFO "Waiting for the server to come back..."
started=0
for _ in $(seq 1 60); do
  if dw_container_running; then started=1; break; fi
  sleep 2
done

if [ "${started}" -ne 1 ]; then
  dw_log ERROR "The server did not restart. Last 60 log lines:"
  dw_compose logs --tail 60 || true
  dw_log ERROR "Restore the pre-update state with: ${DW_SCRIPT_DIR}/restore.sh"
  exit 1
fi

# SteamCMD downloads the delta before the game starts, so give it room.
dw_log INFO "Waiting for SteamCMD to finish downloading the update..."
NEW_BUILD="${INSTALLED_BUILD}"
for _ in $(seq 1 120); do
  sleep 10
  candidate="$(dw_installed_build_id || true)"
  if [ -n "${candidate}" ] && [ "${candidate}" != "${INSTALLED_BUILD}" ]; then
    NEW_BUILD="${candidate}"
    break
  fi
  dw_container_running || break
done

if [ "${NEW_BUILD}" != "${INSTALLED_BUILD}" ]; then
  dw_log INFO "Update applied: ${INSTALLED_BUILD} -> ${NEW_BUILD}"
  rm -f "${PENDING_FLAG}"
elif [ "${FALLBACK_MODE}" -eq 1 ]; then
  dw_log INFO "SteamCMD reported nothing new; the server was already on build ${INSTALLED_BUILD}."
  rm -f "${PENDING_FLAG}"
else
  dw_log WARN "The build id has not changed yet (still ${INSTALLED_BUILD})."
  dw_log WARN "The download may still be running. Check with logs.sh."
fi

if ! dw_container_running; then
  dw_log ERROR "The container stopped during the update. Last 60 log lines:"
  dw_compose logs --tail 60 || true
  exit 1
fi

dw_log INFO "Update finished. The pre-update backup is in ${DW_BACKUP_DIR}/pre-update/."
