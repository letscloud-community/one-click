#!/bin/bash
#
# Runs `hermes setup --portal` on the first interactive root login.
#
# The agent cannot do anything useful until an LLM provider is configured, and
# that step needs a terminal, so it cannot happen during the Packer build nor
# in cloud-init. Offering it right after the MOTD means the customer lands in
# the configuration wizard instead of an unconfigured shell.
#
# Invoked by /etc/profile.d/hermes-first-login.sh. It must never leave the
# login shell in a broken state, so no `set -e` here.

set -u

HERMES_BIN="${HERMES_BIN:-/usr/local/bin/hermes}"
STATE_DIR="${HERMES_STATE_DIR:-/var/lib/hermes}"
MARKER="${STATE_DIR}/first-login.done"

if [ -f "${MARKER}" ]; then
  exit 0
fi

if [ ! -x "${HERMES_BIN}" ]; then
  echo "Hermes launcher not found at ${HERMES_BIN}; skipping the setup wizard."
  echo "Check /var/log/cloud-init-output.log and rerun 'hermes setup --portal' manually."
  exit 0
fi

cat << 'EOF'

-----------------------------------------------------------
 First login: configuring Hermes Agent
-----------------------------------------------------------
Starting 'hermes setup --portal' so you can pick your LLM
provider, model and tools.

Press Ctrl+C to skip; the wizard is offered again on the next
login. To never be prompted again, run:
  touch /var/lib/hermes/first-login.done
-----------------------------------------------------------

EOF

mkdir -p "${STATE_DIR}" 2>/dev/null || true

if "${HERMES_BIN}" setup --portal; then
  # Only a successful run disarms the wizard: an aborted or failed setup
  # leaves the agent unusable, so the customer is prompted again next time.
  : > "${MARKER}" 2>/dev/null || true
  echo
  echo "Hermes Agent is configured. Start it with: hermes"
else
  status=$?
  echo
  echo "Setup did not complete (exit ${status}). It will be offered again on the next login."
  echo "You can also run it manually with: hermes setup --portal"
fi

exit 0
