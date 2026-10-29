#!/bin/bash
#
# Image cleanup before the snapshot.
#
# This is a safer variant of common-scripts/900-cleanup.sh. The shared script
# ends with an unbounded `dd if=/dev/zero of=/zerofile`, which fills the root
# filesystem to 100%. On the 80 GB plan used here that takes a long time and,
# once the disk is full, sshd and journald can no longer write and Packer loses
# the session. It also risks leaving a huge /zerofile behind in the snapshot if
# the build is interrupted.
#
# fstrim achieves the same goal on SSD-backed storage: it tells the underlying
# layer which blocks are free, so they are not carried into the snapshot. A
# bounded zerofill is used only as a fallback, always leaving headroom.

set -uo pipefail

log() { echo "[$(date -u +'%H:%M:%S')] $*"; }

export DEBIAN_FRONTEND=noninteractive

if [ ! -d /tmp ]; then
  mkdir /tmp
fi
chmod 1777 /tmp

log "Removing temporary files..."
rm -rf /tmp/* /var/tmp/* 2>/dev/null || true

log "Clearing shell history..."
history -c 2>/dev/null || true
cat /dev/null > /root/.bash_history 2>/dev/null || true
unset HISTFILE

log "Removing packages that are no longer needed..."
apt-get -y autoremove
apt-get -y autoclean
apt-get -y clean

log "Truncating logs..."
find /var/log -mtime -1 -type f -exec truncate -s 0 {} \; 2>/dev/null || true
rm -rf /var/log/*.gz /var/log/*.[0-9] /var/log/*-???????? 2>/dev/null || true
journalctl --rotate >/dev/null 2>&1 || true
journalctl --vacuum-time=1s >/dev/null 2>&1 || true

log "Removing build artefacts left by the upgrade stage..."
rm -f /var/log/packer-upgrade.log
rm -f /var/lib/packer-upgrade.done
rm -f /usr/local/sbin/packer-upgrade-worker.sh
rm -f /etc/needrestart/conf.d/99-packer.conf

log "Resetting cloud-init so the per-instance scripts run on the customer's first boot..."
rm -rf /var/lib/cloud/instances/* 2>/dev/null || true
rm -f /etc/cloud/cloud-init.disabled

log "Removing host and authorised SSH keys..."
rm -f /root/.ssh/authorized_keys /etc/ssh/*key* 2>/dev/null || true
touch /etc/ssh/revoked_keys
chmod 600 /etc/ssh/revoked_keys

log "Removing the default Ubuntu MOTD fragments..."
rm -rf /etc/update-motd.d/50-landscape-sysinfo
rm -rf /etc/update-motd.d/85-fwupd
rm -rf /etc/update-motd.d/90-updates-available
rm -rf /etc/update-motd.d/91-release-upgrade
rm -rf /etc/update-motd.d/92-unattended-upgrades
rm -rf /etc/update-motd.d/95-hwe-eol
rm -rf /etc/update-motd.d/97-overlayroot
rm -rf /etc/update-motd.d/98-fsck-at-reboot
rm -rf /etc/update-motd.d/98-reboot-required

# --- Reclaim free space ------------------------------------------------------

log "Reclaiming free space..."

TRIMMED=0
if command -v fstrim >/dev/null 2>&1; then
  if fstrim -v / 2>/dev/null; then
    log "fstrim completed on /."
    TRIMMED=1
  else
    log "fstrim is unavailable on this filesystem."
  fi
fi

if [ "${TRIMMED}" -eq 0 ]; then
  # Fallback only. Leave 2 GB free so the system never runs out of space:
  # a full root filesystem stops sshd and journald from writing and would
  # break the build exactly like the shared cleanup script does.
  AVAIL_MB="$(df --output=avail -m / | tail -n1 | tr -d ' ')"
  RESERVE_MB=2048
  FILL_MB=$((AVAIL_MB - RESERVE_MB))

  if [ "${FILL_MB}" -gt 0 ]; then
    log "fstrim unavailable; zeroing ${FILL_MB} MB and keeping ${RESERVE_MB} MB free..."
    dd if=/dev/zero of=/zerofile bs=1M count="${FILL_MB}" status=none 2>/dev/null || true
    sync
    rm -f /zerofile
    sync
    log "Bounded zerofill finished."
  else
    log "Not enough headroom to zerofill safely; skipping."
  fi
fi

log "Final disk usage:"
df -h / | tail -n1

log "Cleanup finished."
