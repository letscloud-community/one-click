#!/bin/bash
#
# Full system upgrade, detached from the SSH session.
#
# The LetsCloud Ubuntu 24.04 base image is several hundred packages behind.
# Upgrading openssh-server, systemd and the kernel over SSH reliably cuts the
# Packer session while dpkg is still processing triggers, which would leave
# packages half configured.
#
# The upgrade is therefore launched as a background job that does not belong to
# the SSH session, so losing the connection cannot abort dpkg. This script only
# starts the job and then waits for it, so the caller may disconnect safely:
# the companion provisioner reconnects and waits for the same marker file.
#
# When the upgrade ends the box reboots itself. That matters: while apt is
# running, sshd, dbus and systemd are restarted several times and the session
# can drop repeatedly. The reboot gives Packer a single, predictable point to
# reconnect to, after which nothing else restarts sshd.
#
# Contract:
#   /var/lib/packer-upgrade.done   appears when finished, contains the exit code
#   /var/log/packer-upgrade.log    full apt output

set -uo pipefail

MARKER="/var/lib/packer-upgrade.done"
LOGFILE="/var/log/packer-upgrade.log"
WORKER="/usr/local/sbin/packer-upgrade-worker.sh"

log() { echo "[$(date -u +'%H:%M:%S')] $*"; }

rm -f "${MARKER}"
: > "${LOGFILE}"

# The worker is a real file rather than an inline command, so no quoting layer
# can mangle it and it can be inspected on the box if a build goes wrong.
cat > "${WORKER}" <<'WORKER_EOF'
#!/bin/bash
exec >>/var/log/packer-upgrade.log 2>&1

export DEBIAN_FRONTEND=noninteractive
export NEEDRESTART_MODE=l
export NEEDRESTART_SUSPEND=1

echo "=== upgrade started at $(date -u) ==="

for _ in $(seq 1 60); do
  fuser /var/lib/dpkg/lock-frontend /var/lib/dpkg/lock \
        /var/lib/apt/lists/lock /var/cache/apt/archives/lock >/dev/null 2>&1 || break
  echo "waiting for apt lock..."
  sleep 5
done

# archive.ubuntu.com sits behind a round robin and individual mirrors do drop
# connections, which makes apt exit 100 halfway through. Retry rather than
# leaving the image partially upgraded.
RC=1
for attempt in 1 2 3 4; do
  echo "--- full-upgrade attempt ${attempt} ---"

  apt-get update -y || true

  apt-get -y \
    -o Dpkg::Options::=--force-confdef \
    -o Dpkg::Options::=--force-confold \
    -o Acquire::Retries=5 \
    --fix-missing \
    full-upgrade
  RC=$?

  # Heal anything dpkg left pending before deciding whether to retry.
  dpkg --configure -a >/dev/null 2>&1 || true
  apt-get -y -f install >/dev/null 2>&1 || true

  if [ "${RC}" -eq 0 ]; then
    PENDING=$(apt-get -s upgrade 2>/dev/null | grep -c '^Inst ' || true)
    if [ "${PENDING}" -eq 0 ]; then
      echo "--- upgrade complete, nothing pending ---"
      break
    fi
    echo "--- apt returned 0 but ${PENDING} packages are still pending; retrying ---"
    RC=1
  fi

  echo "--- attempt ${attempt} failed with rc=${RC}; waiting before retrying ---"
  sleep 20
done

echo "=== upgrade finished at $(date -u) with rc=${RC} ==="
echo "${RC}" > /var/lib/packer-upgrade.done
sync

# Give the waiting provisioner a moment to observe the marker, then reboot so
# the new kernel is live and sshd stops being restarted underneath Packer.
sleep 15
echo "=== rebooting ==="
systemctl reboot || reboot
WORKER_EOF

chmod 0755 "${WORKER}"

# Preferred: run under systemd so the job is completely independent of sshd.
# --no-block matters. Without it systemd-run waits on D-Bus for the job to
# finish, and it dies with "D-Bus connection terminated" the moment the systemd
# package is upgraded underneath it.
STARTED=0
if command -v systemd-run >/dev/null 2>&1; then
  if systemd-run --unit=packer-upgrade --collect --no-block \
       --description="Packer full system upgrade" "${WORKER}" >/dev/null 2>&1; then
    log "Upgrade started as the transient unit packer-upgrade."
    STARTED=1
  else
    log "systemd-run refused the job; falling back to setsid."
  fi
fi

# Fallback: a new session detached from the terminal, so SIGHUP on disconnect
# does not reach it either.
if [ "${STARTED}" -eq 0 ]; then
  setsid nohup "${WORKER}" </dev/null >/dev/null 2>&1 &
  disown || true
  log "Upgrade started as a detached setsid process."
fi

log "Waiting for the upgrade to finish (this takes several minutes)..."

# Roughly 40 minutes. Losing the connection here is fine and expected: the job
# survives, and the provisioners that follow wait for the same marker.
for i in $(seq 1 240); do
  if [ -f "${MARKER}" ]; then
    log "Upgrade finished with exit code $(cat "${MARKER}"). The box will reboot."
    exit 0
  fi
  if [ $((i % 6)) -eq 0 ]; then
    log "Still upgrading... ($((i / 6)) min)"
  fi
  sleep 10
done

log "Still running after the wait window; the next provisioner will keep waiting."
exit 0
