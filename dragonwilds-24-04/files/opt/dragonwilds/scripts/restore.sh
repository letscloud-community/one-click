#!/bin/bash
#
# Restores a RuneScape: Dragonwilds world from a backup archive.
#
# The server is always stopped first: the dedicated server loads the newest
# .sav in SaveGames at startup and holds the world in memory afterwards, so
# swapping files underneath a running server would be overwritten on the next
# autosave.
#
# Usage:
#   restore.sh                      pick a backup from an interactive list
#   restore.sh --list               only list the available backups
#   restore.sh --file <archive>     restore a specific archive
#   restore.sh --latest             restore the most recent backup of any tier
#   restore.sh --file <a> --yes     skip the confirmation prompt

set -euo pipefail

# shellcheck source=/opt/dragonwilds/scripts/common.sh
. /opt/dragonwilds/scripts/common.sh

ARCHIVE=""
ASSUME_YES=0
LIST_ONLY=0
USE_LATEST=0

while [ $# -gt 0 ]; do
  case "$1" in
    --file)   ARCHIVE="${2:-}"; shift 2 ;;
    --list)   LIST_ONLY=1; shift ;;
    --latest) USE_LATEST=1; shift ;;
    --yes|-y) ASSUME_YES=1; shift ;;
    -h|--help)
      sed -n '2,16p' "$0" | sed 's/^# \{0,1\}//'
      exit 0 ;;
    *) echo "Unknown option: $1" >&2; exit 1 ;;
  esac
done

dw_require_root
dw_tee_log restore
dw_load_env

# --- 1. List the available backups -------------------------------------------

mapfile -t BACKUPS < <(
  find "${DW_BACKUP_DIR}" -maxdepth 2 -name 'dragonwilds-*.tar.gz' -printf '%T@\t%p\n' 2>/dev/null \
    | sort -rn \
    | cut -f2-
)

if [ "${#BACKUPS[@]}" -eq 0 ]; then
  dw_die "No backups found under ${DW_BACKUP_DIR}."
fi

print_backup_table() {
  printf '\n  %-4s %-46s %-8s %-19s\n' "#" "ARCHIVE" "SIZE" "CREATED"
  printf '  %s\n' "------------------------------------------------------------------------------"
  local i=1 f
  for f in "${BACKUPS[@]}"; do
    printf '  %-4s %-46s %-8s %-19s\n' \
      "${i}" \
      "$(realpath --relative-to="${DW_BACKUP_DIR}" "${f}")" \
      "$(du -h "${f}" | awk '{print $1}')" \
      "$(date -r "${f}" +'%Y-%m-%d %H:%M:%S')"
    i=$((i + 1))
  done
  echo ""
}

if [ "${LIST_ONLY}" -eq 1 ]; then
  echo "Backups available in ${DW_BACKUP_DIR}:"
  print_backup_table
  exit 0
fi

# --- 2. Choose the archive ---------------------------------------------------

if [ "${USE_LATEST}" -eq 1 ]; then
  ARCHIVE="${BACKUPS[0]}"
fi

if [ -z "${ARCHIVE}" ]; then
  [ -t 0 ] || dw_die "No archive given. Use --file <archive>, --latest or run interactively."

  echo "================================================================================"
  echo "  RuneScape: Dragonwilds  -  Restore a world"
  echo "================================================================================"
  print_backup_table
  read -rp "Number of the backup to restore (or q to quit): " choice
  [ "${choice}" = "q" ] && { echo "Cancelled."; exit 0; }
  if ! printf '%s' "${choice}" | grep -Eq '^[0-9]+$' \
     || [ "${choice}" -lt 1 ] || [ "${choice}" -gt "${#BACKUPS[@]}" ]; then
    dw_die "Invalid selection \"${choice}\"."
  fi
  ARCHIVE="${BACKUPS[$((choice - 1))]}"
fi

# Allow a bare filename or a path relative to the backup directory.
if [ ! -f "${ARCHIVE}" ]; then
  for candidate in "${DW_BACKUP_DIR}/${ARCHIVE}" $(find "${DW_BACKUP_DIR}" -maxdepth 2 -name "$(basename "${ARCHIVE}")" 2>/dev/null); do
    if [ -f "${candidate}" ]; then ARCHIVE="${candidate}"; break; fi
  done
fi
[ -f "${ARCHIVE}" ] || dw_die "Archive not found: ${ARCHIVE}"

# --- 3. Validate the archive before touching anything ------------------------

dw_log INFO "Selected ${ARCHIVE}"

if [ -f "${ARCHIVE}.sha256" ]; then
  dw_log INFO "Checking the checksum..."
  expected="$(cat "${ARCHIVE}.sha256")"
  actual="$(sha256sum "${ARCHIVE}" | awk '{print $1}')"
  [ "${expected}" = "${actual}" ] || dw_die "Checksum mismatch. The archive is damaged."
else
  dw_log WARN "No .sha256 next to the archive; skipping the checksum check."
fi

dw_log INFO "Checking the archive is readable..."
tar -tzf "${ARCHIVE}" >/dev/null 2>&1 || dw_die "The archive is corrupt and cannot be restored."

# grep -c rather than grep -q: with pipefail, the SIGPIPE from an early grep
# exit would fail the pipeline even on a perfectly good archive.
SAV_COUNT="$(tar -tzf "${ARCHIVE}" | grep -c '\.sav$' || true)"
[ "${SAV_COUNT:-0}" -gt 0 ] || dw_die "The archive contains no .sav file."
dw_log INFO "Archive holds ${SAV_COUNT} world file(s)."

if [ "${ASSUME_YES}" -eq 0 ]; then
  [ -t 0 ] || dw_die "Refusing to restore non-interactively without --yes."
  echo ""
  echo "  This will REPLACE the worlds currently on the server with the contents"
  echo "  of ${ARCHIVE}."
  echo ""
  echo "  The server will be stopped, the current state saved to"
  echo "  ${DW_BACKUP_DIR}/pre-restore/, and the server started again."
  echo ""
  read -rp "  Type RESTORE to continue: " confirm
  [ "${confirm}" = "RESTORE" ] || { echo "Cancelled."; exit 0; }
fi

# --- 4. Stop the server ------------------------------------------------------

WAS_RUNNING=0
if dw_container_running; then
  WAS_RUNNING=1
  dw_log INFO "Stopping the server (allowing time for the final save)..."
  dw_compose stop
else
  dw_log INFO "The server is already stopped."
fi

# --- 5. Safety backup of the current state -----------------------------------

if [ -n "$(find "${DW_SAVE_DIR}" -maxdepth 1 -name '*.sav' -print -quit 2>/dev/null)" ]; then
  dw_log INFO "Saving the current state to pre-restore first..."
  if ! "${DW_SCRIPT_DIR}/backup.sh" --tier pre-restore --label "before-restore"; then
    dw_log ERROR "The safety backup failed."
    if [ "${WAS_RUNNING}" -eq 1 ]; then
      dw_log INFO "Restarting the server and aborting the restore."
      dw_compose start || true
    fi
    dw_die "Aborted without changing anything."
  fi
else
  dw_log INFO "No world present, so there is nothing to save first."
fi

# --- 6. Restore --------------------------------------------------------------

dw_log INFO "Extracting into ${DW_DATA_DIR}..."

# Unpack to a staging directory first so a failure halfway through cannot leave
# the live SaveGames folder in a mixed state.
STAGING="$(mktemp -d "${DW_DIR}/.restore-XXXXXX")"
cleanup_staging() { rm -rf "${STAGING}"; }
trap cleanup_staging EXIT

tar -xzf "${ARCHIVE}" -C "${STAGING}" || dw_die "Extraction failed. Nothing was changed."

[ -d "${STAGING}/${DW_SAVE_REL}" ] || dw_die "The archive has an unexpected layout (no ${DW_SAVE_REL})."

dw_log INFO "Swapping in the restored worlds..."
mkdir -p "$(dirname "${DW_SAVE_DIR}")"
rm -rf "${DW_SAVE_DIR}"
mv "${STAGING}/${DW_SAVE_REL}" "${DW_SAVE_DIR}"

# The config is restored too when present, so ServerGuid survives.
if [ -d "${STAGING}/RSDragonwilds/Saved/Config" ]; then
  dw_log INFO "Restoring the server configuration..."
  mkdir -p "${DW_DATA_DIR}/RSDragonwilds/Saved"
  rm -rf "${DW_DATA_DIR}/RSDragonwilds/Saved/Config"
  mv "${STAGING}/RSDragonwilds/Saved/Config" "${DW_DATA_DIR}/RSDragonwilds/Saved/Config"
fi

cleanup_staging
trap - EXIT

# --- 7. Permissions ----------------------------------------------------------

dw_log INFO "Reapplying ownership (${DW_UID}:${DW_GID})..."
dw_fix_permissions

# --- 8. Start the server again -----------------------------------------------

dw_log INFO "Starting the server..."
dw_compose up -d

started=0
for _ in $(seq 1 30); do
  if dw_container_running; then started=1; break; fi
  sleep 2
done

if [ "${started}" -ne 1 ]; then
  dw_log ERROR "The server did not come back up. Last 40 log lines:"
  dw_compose logs --tail 40 || true
  dw_die "Restore finished but the server is down."
fi

dw_log INFO "Restore complete."
dw_log INFO "The world will be available once the server finishes loading; watch logs.sh."
dw_log INFO "The pre-restore copy of the previous state is in ${DW_BACKUP_DIR}/pre-restore/."
