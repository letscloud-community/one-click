#!/bin/bash
#
# RuneScape: Dragonwilds first boot setup.
#
# Collects the parameters the dedicated server needs (above all the Owner ID,
# without which the server refuses to start), writes /opt/dragonwilds/.env,
# pulls the official image and brings the server up.
#
# Runs interactively on the first SSH login, and non-interactively when the
# Owner ID is supplied up front:
#
#   /opt/dragonwilds/scripts/first-boot.sh --owner-id <EOS_ID> --non-interactive
#   DW_OWNER_ID=<EOS_ID> /opt/dragonwilds/scripts/first-boot.sh --non-interactive
#
# It refuses to run twice unless --force is given.

set -euo pipefail

# shellcheck source=/opt/dragonwilds/scripts/common.sh
. /opt/dragonwilds/scripts/common.sh

MARKER="${DW_STATE_DIR}/first-boot.done"

OWNER_ID="${DW_OWNER_ID:-}"
SERVER_NAME="${DW_SERVER_NAME:-}"
WORLD_NAME="${DW_WORLD_NAME:-}"
WORLD_PASSWORD="${DW_WORLD_PASSWORD:-}"
ADMIN_PASSWORD="${DW_ADMIN_PASSWORD:-}"
ADMINS="${DW_ADMINS:-}"
INTERACTIVE=1
FORCE=0
WORLD_PASSWORD_SET=0

# The game port is fixed. The official dedicated server listens on UDP 7777,
# and only a second instance on the same host would move to 7778. This image
# runs one server per VPS, so pinning the value keeps the compose file, the
# UFW rule and the address shown to players permanently in sync.
readonly PORT=7777

# Beacon port, which the Worlds browser uses to advertise and reach the server.
# Mandatory: with it closed the world is listed and then fails to join. The
# convention is game port + 1111.
readonly BEACON_PORT=8888

# Kept within DW_NAME_MAXLEN so the browser shows it in full.
readonly DEFAULT_SERVER_NAME=letscloud-dw

usage() {
  cat <<'EOF'
Usage: first-boot.sh [options]

  --owner-id ID        EOS Online ID of the server owner (required)
  --server-name NAME   Name shown in the "Created By" column
  --world-name NAME    Name players search for in the Worlds browser
  --password PASS      World password ("" for an open server)
  --admin-password P   Password for the Server Management screen
  --admins LIST        Comma separated EOS Online IDs with admin rights
  --non-interactive    Never prompt; fail if the Owner ID is missing
  --force              Run again even if setup already completed
  -h, --help           Show this help

Passwords left unset are generated randomly and printed at the end.
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    --owner-id)       OWNER_ID="${2:-}"; shift 2 ;;
    --server-name)    SERVER_NAME="${2:-}"; shift 2 ;;
    --world-name)     WORLD_NAME="${2:-}"; shift 2 ;;
    --password)       WORLD_PASSWORD="${2:-}"; WORLD_PASSWORD_SET=1; shift 2 ;;
    --admin-password) ADMIN_PASSWORD="${2:-}"; shift 2 ;;
    --admins)         ADMINS="${2:-}"; shift 2 ;;
    --non-interactive) INTERACTIVE=0; shift ;;
    --force)          FORCE=1; shift ;;
    -h|--help)        usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage; exit 1 ;;
  esac
done

dw_require_root
mkdir -p "${DW_STATE_DIR}"
dw_tee_log first-boot

# --- 10. Refuse to run twice -------------------------------------------------

if [ -f "${MARKER}" ] && [ "${FORCE}" -eq 0 ]; then
  dw_log INFO "Setup already completed on $(cat "${MARKER}")."
  dw_log INFO "Re-run with --force to reconfigure, or edit ${DW_ENV_FILE} and run restart.sh."
  exit 0
fi

# Stdin has to be a terminal for the wizard to be usable.
if [ "${INTERACTIVE}" -eq 1 ] && [ ! -t 0 ]; then
  INTERACTIVE=0
fi

# --- 1. Collect and validate parameters --------------------------------------

# EOS Online IDs are 32 hexadecimal characters. Accept anything plausible so a
# future format change does not brick the wizard, but warn loudly.
validate_owner_id() {
  local id="$1"
  [ -n "${id}" ] || { echo "The Owner ID cannot be empty."; return 1; }
  if ! printf '%s' "${id}" | grep -Eq '^[0-9a-zA-Z]{16,64}$'; then
    echo "\"${id}\" does not look like an Owner ID (expected 16-64 alphanumeric characters)."
    return 1
  fi
  if ! printf '%s' "${id}" | grep -Eq '^[0-9a-fA-F]{32}$'; then
    dw_log WARN "Owner ID is not the usual 32 hex characters. Continuing, but double check it."
  fi
  return 0
}

# The world and server names reach the Worlds browser as EOS session attributes
# capped at DW_NAME_MAXLEN. A longer name is truncated there while the local save
# keeps it intact, so the name handed to players would not match what they see.
validate_name() {
  local label="$1" value="$2"
  [ -n "${value}" ] || { echo "The ${label} cannot be empty."; return 1; }
  if [ "${#value}" -gt "${DW_NAME_MAXLEN}" ]; then
    echo "The ${label} has ${#value} characters; the game only advertises the first ${DW_NAME_MAXLEN}."
    echo "It would show up as \"${value:0:${DW_NAME_MAXLEN}}\" and players could not find it. Use a shorter name."
    return 1
  fi
  return 0
}

if [ "${INTERACTIVE}" -eq 1 ]; then
  clear || true
  cat <<'EOF'
================================================================================
          RuneScape: Dragonwilds Dedicated Server  -  Initial Setup
================================================================================

This wizard configures the dedicated server and starts it.

You need your Owner ID before continuing:

  1. Launch RuneScape: Dragonwilds.
  2. Open the Settings menu.
  3. Scroll to the bottom and copy the Player ID shown there.

The server will not start without it.

--------------------------------------------------------------------------------
EOF

  while ! validate_owner_id "${OWNER_ID}"; do
    read -rp "Owner ID (EOS Online ID): " OWNER_ID
    OWNER_ID="$(printf '%s' "${OWNER_ID}" | tr -d '[:space:]')"
  done

  echo ""
  echo "World and server names are limited to ${DW_NAME_MAXLEN} characters: the game truncates"
  echo "anything longer when it advertises the world, and players searching for the"
  echo "full name would never find it."
  echo ""

  default_world="dragon-$(head -c 3 /dev/urandom | od -An -tx1 | tr -d ' \n')"
  while :; do
    read -rp "World name (what players search for) [${default_world}]: " answer
    WORLD_NAME="${answer:-${WORLD_NAME:-${default_world}}}"
    validate_name "World name" "${WORLD_NAME}" && break
    WORLD_NAME=""
  done

  while :; do
    read -rp "Server name (Created By column) [${DEFAULT_SERVER_NAME}]: " answer
    SERVER_NAME="${answer:-${SERVER_NAME:-${DEFAULT_SERVER_NAME}}}"
    validate_name "Server name" "${SERVER_NAME}" && break
    SERVER_NAME=""
  done

  echo ""
  echo "World password. Leave empty to let anyone join, or type one to lock the world."
  read -rp "World password [empty = open server]: " answer
  WORLD_PASSWORD="${answer}"
  WORLD_PASSWORD_SET=1
  echo ""
else
  OWNER_ID="$(printf '%s' "${OWNER_ID}" | tr -d '[:space:]')"
  if ! validate_owner_id "${OWNER_ID}"; then
    dw_log ERROR "No valid Owner ID supplied."
    dw_log ERROR "Run: ${DW_SCRIPT_DIR}/first-boot.sh --owner-id <EOS_ID>"
    exit 1
  fi
fi

SERVER_NAME="${SERVER_NAME:-${DEFAULT_SERVER_NAME}}"
WORLD_NAME="${WORLD_NAME:-dragon-$(head -c 3 /dev/urandom | od -An -tx1 | tr -d ' \n')}"

# Reached non-interactively too, where the names come from flags or cloud-init
# and nobody is around to retype them. Truncating here keeps the .env, the
# summary and the Worlds browser all showing the same string.
for name_var in WORLD_NAME SERVER_NAME; do
  name_value="${!name_var}"
  if [ "${#name_value}" -gt "${DW_NAME_MAXLEN}" ]; then
    dw_log WARN "${name_var} has ${#name_value} characters; the game only advertises the first ${DW_NAME_MAXLEN}."
    name_value="${name_value:0:${DW_NAME_MAXLEN}}"
    printf -v "${name_var}" '%s' "${name_value}"
    dw_log WARN "Using the truncated value \"${name_value}\" so players search for what the browser shows."
  fi
done

# An unset admin password becomes a random one. An unset world password stays
# empty only when it was explicitly requested, otherwise it is generated too.
GENERATED_WORLD_PASSWORD=0
if [ -z "${ADMIN_PASSWORD}" ]; then
  ADMIN_PASSWORD="$(dw_generate_password)"
fi
if [ -z "${WORLD_PASSWORD}" ] && [ "${WORLD_PASSWORD_SET}" -eq 0 ]; then
  WORLD_PASSWORD="$(dw_generate_password)"
  GENERATED_WORLD_PASSWORD=1
fi

# The image reads the literal string "random" as "regenerate on every start",
# which silently changes the password whenever the container restarts.
for var_name in WORLD_PASSWORD ADMIN_PASSWORD; do
  if [ "${!var_name}" = "random" ]; then
    dw_die "\"random\" is a reserved value for passwords. Choose a different one."
  fi
done

dw_log INFO "Owner ID:    ${OWNER_ID}"
dw_log INFO "Server name: ${SERVER_NAME}"
dw_log INFO "World name:  ${WORLD_NAME}"
dw_log INFO "UDP ports:   ${PORT} (game), ${BEACON_PORT} (beacon)"

# --- 2. Make sure Docker is present and running ------------------------------

dw_log INFO "Checking Docker..."
if ! command -v docker >/dev/null 2>&1; then
  dw_log WARN "Docker is missing from this image; installing it now."
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -y
  apt-get install -y ca-certificates curl gnupg
  install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
  chmod a+r /etc/apt/keyrings/docker.gpg
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "${VERSION_CODENAME}") stable" \
    > /etc/apt/sources.list.d/docker.list
  apt-get update -y
  apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
fi

systemctl enable --now docker >/dev/null 2>&1 || true
docker info >/dev/null 2>&1 || dw_die "Docker is installed but not responding."
docker compose version >/dev/null 2>&1 || dw_die "The docker compose plugin is unavailable."

# --- 3. Create the directory tree --------------------------------------------

dw_log INFO "Creating the directory tree under ${DW_DIR}..."
mkdir -p "${DW_DATA_DIR}" "${DW_SCRIPT_DIR}" "${DW_LOG_DIR}" "${DW_STATE_DIR}"
mkdir -p "${DW_BACKUP_DIR}"/{hourly,daily,weekly,manual,pre-update,pre-restore}

# --- 4. Generate the .env ----------------------------------------------------

dw_log INFO "Writing ${DW_ENV_FILE}..."
if [ -f "${DW_ENV_FILE}" ] && [ "${FORCE}" -eq 1 ]; then
  cp -a "${DW_ENV_FILE}" "${DW_ENV_FILE}.bak.$(date +%Y%m%d%H%M%S)"
  dw_log INFO "Previous .env kept as a timestamped .bak file."
fi

# The template is copied with mode 0600 from the outset, so the passwords that
# dw_env_set writes a few lines below are never world readable, not even for
# an instant.
install -m 0600 "${DW_ENV_EXAMPLE}" "${DW_ENV_FILE}"
chown root:root "${DW_ENV_FILE}" 2>/dev/null || true

dw_env_set RSDW_OWNER_ID       "${OWNER_ID}"
dw_env_set RSDW_SERVER_NAME    "${SERVER_NAME}"
dw_env_set RSDW_WORLD_NAME     "${WORLD_NAME}"
dw_env_set RSDW_PORT           "${PORT}"
dw_env_set RSDW_BEACON_PORT    "${BEACON_PORT}"
dw_env_set RSDW_PASSWORD       "${WORLD_PASSWORD}"
dw_env_set RSDW_ADMIN_PASSWORD "${ADMIN_PASSWORD}"
dw_env_set RSDW_ADMINS         "${ADMINS}"

# --- 5. Permissions ----------------------------------------------------------

dw_log INFO "Applying ownership for the container user (${DW_UID}:${DW_GID})..."
dw_fix_permissions
chmod 0700 "${DW_BACKUP_DIR}"
chmod 0755 "${DW_DIR}"
chmod 0750 "${DW_LOG_DIR}"

# --- Firewall ----------------------------------------------------------------

# firewall.sh verifies that SSH is allowed before enabling anything, and
# reloads instead of cycling the firewall when it is already active, so the
# session running this wizard is never cut.
if [ -x "${DW_SCRIPT_DIR}/firewall.sh" ]; then
  dw_log INFO "Applying the firewall policy (SSH plus UDP/${PORT} and UDP/${BEACON_PORT})..."
  if ! "${DW_SCRIPT_DIR}/firewall.sh"; then
    dw_log WARN "The firewall was not enabled. The server still works; run"
    dw_log WARN "${DW_SCRIPT_DIR}/firewall.sh manually to inspect the problem."
  fi
fi

# --- 6. Pull the official image ----------------------------------------------

dw_log INFO "Pulling the official image ghcr.io/runescape/rsdw-dedicated..."
if ! dw_compose pull; then
  dw_log WARN "Pull failed; falling back to the copy baked into the image."
fi

# --- 7. Start the server -----------------------------------------------------

dw_log INFO "Starting the dedicated server..."
dw_log INFO "The first start downloads roughly 5.5 GB through SteamCMD, which usually takes a few minutes."
dw_compose up -d --remove-orphans

systemctl enable dragonwilds.service >/dev/null 2>&1 || true
systemctl enable --now dragonwilds-backup.timer >/dev/null 2>&1 || true
systemctl enable --now dragonwilds-update.timer >/dev/null 2>&1 || true

# --- 8. Verify the container is healthy --------------------------------------

dw_log INFO "Waiting for the container to settle..."
started=0
for _ in $(seq 1 30); do
  if dw_container_running; then
    started=1
    break
  fi
  sleep 2
done

if [ "${started}" -ne 1 ]; then
  dw_log ERROR "The container is not running. Last 40 log lines:"
  dw_compose logs --tail 40 || true
  dw_die "Startup failed. Fix the problem and re-run with --force."
fi

# A container that starts and immediately exits usually means a bad Owner ID.
sleep 10
if ! dw_container_running; then
  dw_log ERROR "The container exited shortly after starting. Last 40 log lines:"
  dw_compose logs --tail 40 || true
  dw_die "Startup failed. The most common cause is an invalid Owner ID."
fi

# -4 matters: the game port is published over IPv4 and an IPv6 answer would
# produce an address that players cannot use.
MYIP="$(curl -4 -fsSL --max-time 10 https://ifconfig.me 2>/dev/null \
  || curl -4 -fsSL --max-time 10 https://api.ipify.org 2>/dev/null \
  || hostname -I | awk '{print $1}')"

# Published once the world finishes loading, which is well after the container
# starts, so it may not exist yet on this very first run.
JOIN_CODE="$(dw_join_code)"

# --- 9. Record the result ----------------------------------------------------

date -u +'%Y-%m-%dT%H:%M:%SZ' > "${MARKER}"
chmod 0600 "${MARKER}"

INFO_FILE="/root/dragonwilds_info.txt"
{
  cat <<EOF
================================================================================
RuneScape: Dragonwilds Dedicated Server
================================================================================

The server is starting. SteamCMD downloads the game (about 5.5 GB) on this
first run, so allow a few minutes before the world shows up in the browser.

  Watch progress with: /opt/dragonwilds/scripts/logs.sh

--------------------------------------------------------------------------------
How players join
--------------------------------------------------------------------------------

  1. Worlds screen > Public tab.
  2. Search for the world name EXACTLY as written below (case sensitive).
     The game advertises at most ${DW_NAME_MAXLEN} characters, so the name below is
     already what the browser shows.

  World name:     ${WORLD_NAME}
  Server name:    ${SERVER_NAME}
  Address:        ${MYIP}:${PORT}/udp
  Beacon port:    ${BEACON_PORT}/udp (used by the Worlds browser, already open)
  Owner ID:       ${OWNER_ID}

EOF
  if [ -n "${JOIN_CODE}" ]; then
    cat <<EOF
  Join code:      ${JOIN_CODE}

  The join code is the quickest way in and skips the search entirely. It is
  regenerated whenever the container is recreated; read the current one with
  ${DW_SCRIPT_DIR}/status.sh.

EOF
  else
    cat <<EOF
  Join code:      not published yet (the world is still loading)

  The join code skips the search entirely. Read it once the world is up with
  ${DW_SCRIPT_DIR}/status.sh.

EOF
  fi
  cat <<EOF
--------------------------------------------------------------------------------
Credentials
--------------------------------------------------------------------------------

EOF
  if [ -z "${WORLD_PASSWORD}" ]; then
    echo "  World password:  (none, the world is open to everyone)"
  elif [ "${GENERATED_WORLD_PASSWORD}" -eq 1 ]; then
    echo "  World password:  ${WORLD_PASSWORD}   (generated, share it with your players)"
  else
    echo "  World password:  ${WORLD_PASSWORD}"
  fi
  cat <<EOF
  Admin password:  ${ADMIN_PASSWORD}

  The admin password unlocks Pause Menu > Settings > Server Management.
  Both are stored in ${DW_ENV_FILE} (root only, mode 600).

--------------------------------------------------------------------------------
Management
--------------------------------------------------------------------------------

  /opt/dragonwilds/scripts/status.sh     Server status and connection details
  /opt/dragonwilds/scripts/logs.sh       Follow the live logs
  /opt/dragonwilds/scripts/start.sh      Start the server
  /opt/dragonwilds/scripts/stop.sh       Stop the server (saves first)
  /opt/dragonwilds/scripts/restart.sh    Restart and apply .env changes
  /opt/dragonwilds/scripts/update.sh     Check for and apply game updates
  /opt/dragonwilds/scripts/backup.sh     Back up the worlds now
  /opt/dragonwilds/scripts/restore.sh    Restore a world from a backup

  Configuration:  ${DW_ENV_FILE}
  Worlds:         ${DW_SAVE_DIR}
  Backups:        ${DW_BACKUP_DIR}

  Backups run hourly and updates are checked hourly, both via systemd timers.

================================================================================
EOF
} > "${INFO_FILE}"
chmod 600 "${INFO_FILE}"

# Stop the wizard from greeting the next login.
sed -i '/first-boot.sh/d' /root/.bashrc 2>/dev/null || true

dw_log INFO "First boot setup completed."

if [ "${INTERACTIVE}" -eq 1 ]; then
  echo ""
  cat "${INFO_FILE}"
  echo ""
  echo "This summary is saved at ${INFO_FILE}"
  echo ""
  read -rp "Press ENTER to continue..." _ || true
  clear || true
else
  dw_log INFO "Summary written to ${INFO_FILE}"
fi
