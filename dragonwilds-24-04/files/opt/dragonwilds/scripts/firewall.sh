#!/bin/bash
#
# Applies the firewall policy without ever locking SSH out.
#
# The default policy is "deny incoming", so enabling UFW while the SSH rule is
# missing leaves the box unreachable and only a rescue console can recover it.
# Every step here is therefore verified rather than assumed, and the firewall is
# only enabled once port 22 is confirmed to be allowed.
#
# Usage:
#   firewall.sh            apply the rules and enable UFW
#   firewall.sh --status   only show the current state
#
# The game and beacon ports come from RSDW_PORT and RSDW_BEACON_PORT in
# /opt/dragonwilds/.env when that file already exists, and fall back to 7777
# and 8888 otherwise. Both are required: the beacon port is what the Worlds
# browser uses to advertise and reach the server, so leaving it closed makes
# the world appear in the list and then fail to join.

set -uo pipefail

DW_DIR="/opt/dragonwilds"
DW_ENV_FILE="${DW_DIR}/.env"
SSH_PORT=22

log() { printf '[%s] [%s] %s\n' "$(date -u +'%Y-%m-%dT%H:%M:%SZ')" "$1" "${*:2}"; }

if [ "$(id -u)" -ne 0 ]; then
  echo "This script must be run as root." >&2
  exit 1
fi

if ! command -v ufw >/dev/null 2>&1; then
  log WARN "ufw is not installed; nothing to do."
  exit 0
fi

# Read the configured game port without sourcing the file, which may hold
# passwords containing shell metacharacters.
GAME_PORT="$(sed -n 's/^RSDW_PORT=//p' "${DW_ENV_FILE}" 2>/dev/null | tail -n1 | tr -d '[:space:]')"
case "${GAME_PORT}" in
  ''|*[!0-9]*) GAME_PORT=7777 ;;
esac

BEACON_PORT="$(sed -n 's/^RSDW_BEACON_PORT=//p' "${DW_ENV_FILE}" 2>/dev/null | tail -n1 | tr -d '[:space:]')"
case "${BEACON_PORT}" in
  ''|*[!0-9]*) BEACON_PORT=8888 ;;
esac

if [ "${1:-}" = "--status" ]; then
  ufw status verbose
  exit 0
fi

# Pick up the port sshd actually listens on, in case it was changed.
DETECTED_SSH_PORT="$(sed -n 's/^[[:space:]]*Port[[:space:]]\+\([0-9]\+\).*/\1/p' /etc/ssh/sshd_config 2>/dev/null | head -n1)"
if [ -n "${DETECTED_SSH_PORT}" ]; then
  SSH_PORT="${DETECTED_SSH_PORT}"
fi

log INFO "Configuring the firewall: SSH ${SSH_PORT}/tcp, game ${GAME_PORT}/udp and beacon ${BEACON_PORT}/udp."

ufw default deny incoming  >/dev/null || log WARN "Could not set the incoming policy."
ufw default allow outgoing >/dev/null || log WARN "Could not set the outgoing policy."

# SSH first and unconditionally, so a later failure can never leave the box
# unreachable.
ufw allow "${SSH_PORT}/tcp" comment 'SSH' >/dev/null 2>&1 \
  || ufw allow "${SSH_PORT}/tcp" >/dev/null 2>&1 \
  || log WARN "Adding the SSH rule reported an error."

ufw allow "${GAME_PORT}/udp" comment 'RuneScape Dragonwilds game' >/dev/null 2>&1 \
  || ufw allow "${GAME_PORT}/udp" >/dev/null 2>&1 \
  || log WARN "Adding the game rule reported an error."

if [ "${BEACON_PORT}" != "${GAME_PORT}" ]; then
  ufw allow "${BEACON_PORT}/udp" comment 'RuneScape Dragonwilds beacon' >/dev/null 2>&1 \
    || ufw allow "${BEACON_PORT}/udp" >/dev/null 2>&1 \
    || log WARN "Adding the beacon rule reported an error."
fi

# Verify the SSH rule really is registered. `ufw show added` lists rules even
# while the firewall is inactive, unlike `ufw status`.
ssh_rule_present() {
  ufw show added 2>/dev/null | grep -qE "(^|[[:space:]])${SSH_PORT}/tcp([[:space:]]|$)" && return 0
  grep -qE "^### tuple ### allow tcp ${SSH_PORT} " /etc/ufw/user.rules 2>/dev/null && return 0
  ufw status 2>/dev/null | grep -qE "^${SSH_PORT}/tcp" && return 0
  return 1
}

if ! ssh_rule_present; then
  log WARN "The SSH rule is still missing; retrying once."
  ufw allow ssh >/dev/null 2>&1 || true
fi

if ! ssh_rule_present; then
  log ERROR "Refusing to enable the firewall: port ${SSH_PORT}/tcp is not allowed."
  log ERROR "Enabling it now would lock this server out. Current rules:"
  ufw show added 2>/dev/null || true
  exit 1
fi

log INFO "SSH rule confirmed."

# Anchor the match: a plain grep for "active" also matches "inactive", which
# would send a disabled firewall down the reload path and leave it switched off.
if ufw status 2>/dev/null | head -n1 | grep -qE '^Status:[[:space:]]+active[[:space:]]*$'; then
  # Already active. Reloading applies the new rules without the brief window
  # that a disable/enable cycle would open on the live SSH session.
  log INFO "Firewall already active; reloading the rules."
  ufw reload >/dev/null 2>&1 || log WARN "Reload reported an error."
else
  log INFO "Firewall inactive; enabling it now..."
  ufw --force enable >/dev/null 2>&1 || log WARN "Enable reported an error."
fi

if ufw status 2>/dev/null | head -n1 | grep -qE '^Status:[[:space:]]+active[[:space:]]*$'; then
  log INFO "Firewall is active."
else
  log WARN "The firewall is still inactive. Inspect it with: ufw status verbose"
fi

log INFO "Current firewall state:"
ufw status verbose 2>/dev/null | sed 's/^/    /'

# Published container ports are opened by Docker directly in iptables, so the
# game is reachable even though UFW sits in front. The explicit UDP rule is
# kept so the intent stays visible in `ufw status`.
