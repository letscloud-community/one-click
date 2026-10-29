#!/bin/bash
#
# Shared helpers for the RuneScape: Dragonwilds management scripts.
# Sourced, never executed directly.

DW_DIR="/opt/dragonwilds"
DW_ENV_FILE="${DW_DIR}/.env"
DW_ENV_EXAMPLE="${DW_DIR}/env.example"
DW_COMPOSE_FILE="${DW_DIR}/docker-compose.yml"
DW_DATA_DIR="${DW_DIR}/data"
DW_BACKUP_DIR="${DW_DIR}/backups"
DW_SCRIPT_DIR="${DW_DIR}/scripts"
DW_LOG_DIR="/var/log/dragonwilds"
DW_STATE_DIR="/var/lib/dragonwilds"

DW_CONTAINER="dragonwilds"

# The game advertises the world name and the server name to the Worlds browser
# as EOS session attributes that are capped at 16 characters. Anything longer is
# silently truncated ("SlotName truncated to fit max length" in the server log)
# while the local save keeps the full name, so players searching for the name
# they were given would never find the world.
DW_NAME_MAXLEN=16

# Layout created by the official image underneath STEAMAPPDIR.
DW_SAVE_REL="RSDragonwilds/Saved/SaveGames"
DW_CONFIG_REL="RSDragonwilds/Saved/Config/LinuxServer/DedicatedServer.ini"
DW_GAMELOG_REL="RSDragonwilds/Saved/Logs/RSDragonwilds.log"
DW_SAVE_DIR="${DW_DATA_DIR}/${DW_SAVE_REL}"

# The official image runs as uid/gid 1000 (the "steam" user) and cannot chown
# its own bind mount, so the host has to own the data directory numerically.
DW_UID=1000
DW_GID=1000

# Steam application id of "RuneScape: Dragonwilds - Dedicated Servers".
DW_STEAM_APPID=4019830
DW_STEAM_UPTODATE_API="https://api.steampowered.com/ISteamApps/UpToDateCheck/v1/"

dw_log() {
  local level="$1"; shift
  printf '[%s] [%s] %s\n' "$(date -u +'%Y-%m-%dT%H:%M:%SZ')" "${level}" "$*"
}

dw_die() {
  dw_log ERROR "$*"
  exit 1
}

dw_require_root() {
  [ "$(id -u)" -eq 0 ] || dw_die "This script must be run as root."
}

# Appends every line of output to a rotated log file while keeping it on stdout.
dw_tee_log() {
  local name="$1"
  mkdir -p "${DW_LOG_DIR}"
  chmod 750 "${DW_LOG_DIR}"
  exec > >(tee -a "${DW_LOG_DIR}/${name}.log") 2>&1
}

# Loads the .env into the environment.
#
# The file is parsed rather than sourced. Values are stored unquoted so that
# docker compose reads them literally, which means a password containing a
# space, a pipe or an ampersand would be executed as shell code by `.`.
dw_load_env() {
  [ -f "${DW_ENV_FILE}" ] || dw_die "${DW_ENV_FILE} not found. Run ${DW_SCRIPT_DIR}/first-boot.sh first."

  local line key value
  while IFS= read -r line || [ -n "${line}" ]; do
    # Skip blank lines and comments.
    case "${line}" in
      ''|'#'*) continue ;;
    esac
    # Only accept well formed KEY=VALUE lines.
    case "${line}" in
      *=*) ;;
      *) continue ;;
    esac
    key="${line%%=*}"
    value="${line#*=}"
    # Reject anything that is not a plain shell identifier.
    printf '%s' "${key}" | grep -Eq '^[A-Za-z_][A-Za-z0-9_]*$' || continue
    # Strip one layer of surrounding quotes if present.
    case "${value}" in
      \"*\") value="${value:1:${#value}-2}" ;;
      \'*\') value="${value:1:${#value}-2}" ;;
    esac
    # printf -v assigns literally: no expansion, no command substitution.
    printf -v "${key}" '%s' "${value}"
    export "${key?}"
  done < "${DW_ENV_FILE}"
}

# docker compose bound to this project, with the .env used for interpolation.
dw_compose() {
  docker compose \
    --project-directory "${DW_DIR}" \
    --env-file "${DW_ENV_FILE}" \
    -f "${DW_COMPOSE_FILE}" \
    "$@"
}

dw_container_running() {
  [ "$(docker inspect -f '{{.State.Running}}' "${DW_CONTAINER}" 2>/dev/null)" = "true" ]
}

# Reads a single key from the .env without sourcing it.
dw_env_get() {
  local key="$1"
  sed -n "s/^${key}=//p" "${DW_ENV_FILE}" 2>/dev/null | tail -n1
}

# Writes or replaces a key in the .env, preserving the rest of the file.
# Uses awk rather than sed so that values containing /, | or & are safe.
dw_env_set() {
  local key="$1" value="$2" tmp
  tmp="$(mktemp)"
  awk -v k="${key}" -v v="${value}" '
    BEGIN { done = 0 }
    index($0, k "=") == 1 { if (!done) { print k "=" v; done = 1 }; next }
    { print }
    END { if (!done) print k "=" v }
  ' "${DW_ENV_FILE}" > "${tmp}"
  # Redirect into the original file so its owner and mode are preserved.
  cat "${tmp}" > "${DW_ENV_FILE}"
  rm -f "${tmp}"
}

# Best effort count of connected players, based on conntrack entries against
# the published UDP game port. Returns 0 when it cannot tell, and callers treat
# a non-zero exit as "unknown".
dw_player_count() {
  local port="${RSDW_PORT:-7777}"
  command -v conntrack >/dev/null 2>&1 || return 1
  conntrack -L -p udp --dport "${port}" 2>/dev/null | grep -c . || true
}

# The Steam build id currently installed inside the data volume.
dw_installed_build_id() {
  local manifest="${DW_DATA_DIR}/steamapps/appmanifest_${DW_STEAM_APPID}.acf"
  [ -f "${manifest}" ] || return 1
  sed -n 's/.*"buildid"[[:space:]]*"\([0-9]\+\)".*/\1/p' "${manifest}" | head -n1
}

# Re-applies the ownership the container expects. Cheap and idempotent.
dw_fix_permissions() {
  mkdir -p "${DW_DATA_DIR}"
  chown -R "${DW_UID}:${DW_GID}" "${DW_DATA_DIR}"
  chmod 0750 "${DW_DATA_DIR}"
  [ -f "${DW_ENV_FILE}" ] && chown root:root "${DW_ENV_FILE}" && chmod 0600 "${DW_ENV_FILE}"
  return 0
}

# The join code the server publishes to EOS on every start. It lets players jump
# straight in without searching the Worlds browser, and it changes whenever the
# container is recreated, so it is always read from the live log.
dw_join_code() {
  docker logs "${DW_CONTAINER}" 2>&1 \
    | sed -n 's/.*"JoinCode"\] written with key\[xz\] value\[\([A-Z0-9-]\{1,\}\)\].*/\1/p' \
    | tail -n1
}

dw_generate_password() {
  # 20 URL-safe characters, no shell metacharacters, no ambiguous glyphs.
  openssl rand -base64 48 | tr -dc 'A-HJ-NP-Za-km-z2-9' | head -c 20
}
