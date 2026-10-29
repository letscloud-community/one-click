#!/bin/bash
#
# Backs up the RuneScape: Dragonwilds worlds.
#
# What gets archived:
#   RSDragonwilds/Saved/SaveGames   the world .sav files
#   RSDragonwilds/Saved/Config      DedicatedServer.ini, which holds ServerGuid
#
# The ~5.5 GB game install is deliberately excluded: SteamCMD can always
# redownload it, and including it would make hourly backups impossible.
#
# Consistency
# -----------
# The dedicated server has no "flush to disk on demand" command, so there are
# two options:
#
#   hot  (default) copy the .sav files without touching the server, after
#        checking that each file has stopped changing. The game autosaves
#        periodically rather than continuously, so this almost always lands
#        between writes, and the archive is verified before being kept.
#
#   cold (--cold, or DW_BACKUP_COLD=true) stop the container, copy, start it
#        again. The only way to be strictly certain a save is complete, at the
#        cost of a short outage. Used automatically before updates and restores.
#
# Usage:
#   backup.sh                 one-off backup into backups/manual
#   backup.sh --auto          tier chosen from the clock (used by the timer)
#   backup.sh --tier daily    force a specific tier
#   backup.sh --cold          stop the server for a guaranteed consistent copy
#   backup.sh --label before-mod-install

set -euo pipefail

# shellcheck source=/opt/dragonwilds/scripts/common.sh
. /opt/dragonwilds/scripts/common.sh

TIER="manual"
AUTO=0
COLD=0
LABEL=""

while [ $# -gt 0 ]; do
  case "$1" in
    --auto)  AUTO=1; shift ;;
    --tier)  TIER="${2:-manual}"; shift 2 ;;
    --cold)  COLD=1; shift ;;
    --label) LABEL="${2:-}"; shift 2 ;;
    -h|--help)
      sed -n '2,30p' "$0" | sed 's/^# \{0,1\}//'
      exit 0 ;;
    *) echo "Unknown option: $1" >&2; exit 1 ;;
  esac
done

dw_require_root
dw_tee_log backup
dw_load_env

[ "${DW_BACKUP_COLD:-false}" = "true" ] && COLD=1

KEEP_HOURLY="${DW_KEEP_HOURLY:-24}"
KEEP_DAILY="${DW_KEEP_DAILY:-7}"
KEEP_WEEKLY="${DW_KEEP_WEEKLY:-4}"

# --- Which tiers to write ----------------------------------------------------

TIERS=()
if [ "${AUTO}" -eq 1 ]; then
  hour="$(date +%-H)"
  dow="$(date +%u)"   # 1 = Monday .. 7 = Sunday
  TIERS+=("hourly")
  # Promote the 04:00 run to a daily copy, and Sunday's to a weekly one, by
  # hardlinking rather than re-reading the saves.
  [ "${hour}" -eq 4 ] && TIERS+=("daily")
  [ "${hour}" -eq 4 ] && [ "${dow}" -eq 7 ] && TIERS+=("weekly")
else
  TIERS+=("${TIER}")
fi

for t in "${TIERS[@]}"; do
  case "${t}" in
    hourly|daily|weekly|manual|pre-restore|pre-update) ;;
    *) dw_die "Unknown tier \"${t}\"." ;;
  esac
done

# --- Nothing to do? ----------------------------------------------------------

if [ ! -d "${DW_SAVE_DIR}" ]; then
  dw_log WARN "${DW_SAVE_DIR} does not exist yet; the server has not created a world."
  exit 0
fi

if [ -z "$(find "${DW_SAVE_DIR}" -maxdepth 1 -name '*.sav' -print -quit 2>/dev/null)" ]; then
  dw_log WARN "No .sav files found in ${DW_SAVE_DIR}; skipping backup."
  exit 0
fi

# --- Consistency window ------------------------------------------------------

# Returns a fingerprint of every save file, so two samples can be compared.
saves_fingerprint() {
  find "${DW_SAVE_DIR}" -maxdepth 1 -name '*.sav' -printf '%p %s %T@\n' 2>/dev/null | sort
}

wait_for_quiet_saves() {
  local attempts=10 before after
  while [ "${attempts}" -gt 0 ]; do
    before="$(saves_fingerprint)"
    sleep 3
    after="$(saves_fingerprint)"
    if [ "${before}" = "${after}" ]; then
      return 0
    fi
    dw_log INFO "A save is still being written; waiting for it to finish..."
    attempts=$((attempts - 1))
  done
  dw_log WARN "Saves kept changing for 30s; archiving anyway and verifying the result."
  return 1
}

RESTART_AFTER=0
if [ "${COLD}" -eq 1 ]; then
  if dw_container_running; then
    dw_log INFO "Cold backup: stopping the server so the world is flushed to disk..."
    dw_compose stop
    RESTART_AFTER=1
  else
    dw_log INFO "Cold backup: the server is already stopped."
  fi
else
  if dw_container_running; then
    dw_log INFO "Hot backup: waiting for a quiet moment between autosaves..."
    wait_for_quiet_saves || true
  fi
fi

# Always bring the server back, even if the archiving below fails.
restore_service() {
  if [ "${RESTART_AFTER}" -eq 1 ]; then
    dw_log INFO "Starting the server again..."
    dw_compose start || dw_log ERROR "Failed to restart the server. Run start.sh manually."
    RESTART_AFTER=0
  fi
}
trap restore_service EXIT

# --- Archive -----------------------------------------------------------------

STAMP="$(date +%Y%m%d-%H%M%S)"
NAME="dragonwilds-${TIERS[0]}-${STAMP}"
[ -n "${LABEL}" ] && NAME="dragonwilds-${TIERS[0]}-${STAMP}-$(printf '%s' "${LABEL}" | tr -cd '[:alnum:]._-')"

PRIMARY_DIR="${DW_BACKUP_DIR}/${TIERS[0]}"
mkdir -p "${PRIMARY_DIR}"
chmod 0700 "${PRIMARY_DIR}"

ARCHIVE="${PRIMARY_DIR}/${NAME}.tar.gz"
TMP_ARCHIVE="${ARCHIVE}.partial"

dw_log INFO "Creating ${ARCHIVE}..."

TAR_PATHS=("${DW_SAVE_REL}")
[ -d "${DW_DATA_DIR}/RSDragonwilds/Saved/Config" ] && TAR_PATHS+=("RSDragonwilds/Saved/Config")

# --warning=no-file-changed keeps tar quiet about files the game touches while
# we read them; the verification step below is what actually decides.
TAR_RC=0
tar -czf "${TMP_ARCHIVE}" \
    --warning=no-file-changed \
    --warning=no-file-removed \
    -C "${DW_DATA_DIR}" \
    "${TAR_PATHS[@]}" 2>/dev/null || TAR_RC=$?

# Exit code 1 means "a file changed while being read", which is recoverable.
# Anything above that is a real failure.
if [ "${TAR_RC}" -gt 1 ]; then
  rm -f "${TMP_ARCHIVE}"
  dw_die "tar failed with exit code ${TAR_RC}."
elif [ "${TAR_RC}" -eq 1 ]; then
  dw_log WARN "tar reported changed files during the read; verifying the archive."
fi

dw_log INFO "Verifying the archive..."
if ! tar -tzf "${TMP_ARCHIVE}" >/dev/null 2>&1; then
  rm -f "${TMP_ARCHIVE}"
  dw_die "The archive is corrupt and was discarded. Re-run with --cold for a guaranteed copy."
fi

# grep -c rather than grep -q: with pipefail, grep -q exits at the first match
# and the SIGPIPE it sends to tar would fail the whole pipeline.
SAV_COUNT="$(tar -tzf "${TMP_ARCHIVE}" | grep -c '\.sav$' || true)"
if [ "${SAV_COUNT:-0}" -eq 0 ]; then
  rm -f "${TMP_ARCHIVE}"
  dw_die "The archive contains no .sav file and was discarded."
fi
dw_log INFO "Archive holds ${SAV_COUNT} world file(s)."

mv "${TMP_ARCHIVE}" "${ARCHIVE}"
chmod 0600 "${ARCHIVE}"
sha256sum "${ARCHIVE}" | awk '{print $1}' > "${ARCHIVE}.sha256"
chmod 0600 "${ARCHIVE}.sha256"

SIZE="$(du -h "${ARCHIVE}" | awk '{print $1}')"
dw_log INFO "Backup complete: ${ARCHIVE} (${SIZE})"

restore_service
trap - EXIT

# --- Promote to the other tiers ----------------------------------------------

for t in "${TIERS[@]:1}"; do
  target_dir="${DW_BACKUP_DIR}/${t}"
  mkdir -p "${target_dir}"
  chmod 0700 "${target_dir}"
  target="${target_dir}/dragonwilds-${t}-${STAMP}.tar.gz"
  # Hardlink so a daily and a weekly copy of the same run cost one archive.
  ln -f "${ARCHIVE}" "${target}" 2>/dev/null || cp -a "${ARCHIVE}" "${target}"
  ln -f "${ARCHIVE}.sha256" "${target}.sha256" 2>/dev/null || cp -a "${ARCHIVE}.sha256" "${target}.sha256"
  dw_log INFO "Also kept as ${target}"
done

# --- Retention ---------------------------------------------------------------

prune() {
  local dir="$1" keep="$2" count
  [ -d "${dir}" ] || return 0
  count="$(find "${dir}" -maxdepth 1 -name 'dragonwilds-*.tar.gz' | wc -l)"
  [ "${count}" -le "${keep}" ] && return 0
  dw_log INFO "Pruning $(basename "${dir}"): keeping the newest ${keep} of ${count}."
  find "${dir}" -maxdepth 1 -name 'dragonwilds-*.tar.gz' -printf '%T@ %p\n' \
    | sort -rn \
    | tail -n +"$((keep + 1))" \
    | cut -d' ' -f2- \
    | while IFS= read -r old; do
        dw_log INFO "Removing $(basename "${old}")"
        rm -f "${old}" "${old}.sha256"
      done
}

prune "${DW_BACKUP_DIR}/hourly" "${KEEP_HOURLY}"
prune "${DW_BACKUP_DIR}/daily"  "${KEEP_DAILY}"
prune "${DW_BACKUP_DIR}/weekly" "${KEEP_WEEKLY}"
prune "${DW_BACKUP_DIR}/pre-update" 5
prune "${DW_BACKUP_DIR}/pre-restore" 5

# --- Disk space warning ------------------------------------------------------

AVAIL_PCT="$(df --output=pcent "${DW_DIR}" | tail -n1 | tr -dc '0-9')"
if [ -n "${AVAIL_PCT}" ] && [ "${AVAIL_PCT}" -ge 90 ]; then
  dw_log WARN "The filesystem holding ${DW_DIR} is ${AVAIL_PCT}% full. Reduce DW_KEEP_* or copy backups off the server."
fi

dw_log INFO "Done."
