#!/bin/bash
#
# Per-instance first boot work for the Hermes Agent image.
#
# The LetsCloud ubuntu-26.04-x86_64 base image does not ship cloud-init, so the
# usual /var/lib/cloud/scripts/per-instance hook never runs. This script is
# driven by hermes-firstboot.service instead.
#
# It must never fail the boot, so no `set -e` here.

set -u

STATE_DIR=/var/lib/hermes
STAMP="${STATE_DIR}/first-boot.done"

if [ -f "${STAMP}" ]; then
  exit 0
fi

mkdir -p "${STATE_DIR}"

# systemd runs with a minimal PATH and does not read root's shell rc files, so
# the launcher is checked through its absolute path.
if ! /usr/local/bin/hermes --help >/dev/null 2>&1; then
  echo "Hermes command not working. Check 'journalctl -u hermes-firstboot' and rebuild the image." >&2
fi

# A new instance must always be offered the setup wizard, even when the image
# was snapshotted from a machine that had already been configured.
rm -f "${STATE_DIR}/first-login.done"

: > "${STAMP}"
exit 0
