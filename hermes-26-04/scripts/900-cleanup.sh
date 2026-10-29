#!/bin/bash
#
# Image cleanup before the snapshot.
#
# Safer variant of common-scripts/900-cleanup.sh. The shared script ends with an
# unbounded `dd if=/dev/zero of=/zerofile`, which fills the root filesystem to
# 100%. Once the disk is full sshd and journald can no longer write and Packer
# loses the session; an interrupted build also leaves a huge /zerofile inside
# the snapshot.
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

log "Removing Hermes installer artefacts..."
# Install logs and telemetry receipts are specific to this build host and must
# not be inherited by every deployed instance. The install itself, under
# /root/.hermes/hermes-agent, is deliberately kept.
rm -rf /root/.hermes/logs 2>/dev/null || true
rm -rf /root/.hermes/telemetry 2>/dev/null || true
rm -f /tmp/hermes-install.sh 2>/dev/null || true

log "Rearming the first-login and first-boot hooks..."
# Markers inside the snapshot would silently skip the wizard on every deployed
# instance, and would stop hermes-firstboot.service from ever running.
rm -f /var/lib/hermes/first-login.done 2>/dev/null || true
rm -f /var/lib/hermes/first-boot.done 2>/dev/null || true

log "Resetting cloud-init in case the base image ever ships it..."
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

# --- Flush everything to disk ------------------------------------------------

# The snapshot is taken from the block device, not from the running kernel's
# page cache. Without this, any file written late in the build can land in the
# image as a correctly sized but NUL-filled tail. That is not theoretical: the
# first build of this image lost the end of /etc/ssh/sshd_config exactly this
# way, because the only `sync` calls lived inside the zerofill fallback below
# and fstrim succeeded, so they never ran.
log "Flushing pending writes to disk..."
sync
sync

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

log "Final flush before the snapshot..."
sync
sync

log "Final disk usage:"
df -h / | tail -n1

log "Cleanup finished."
