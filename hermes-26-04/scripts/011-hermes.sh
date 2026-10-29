#!/bin/bash

# Hermes Agent Installation Script for Ubuntu 26.04
#
# The official installer is a per-user install: it unpacks into
# $HERMES_HOME/hermes-agent (/root/.hermes/hermes-agent here), publishes the
# launcher in ~/.local/bin and puts that directory on PATH by appending to
# ~/.bashrc and ~/.profile. Neither file is read by the non-interactive shell
# Packer uses, nor by cloud-init, so this script resolves the launcher by path
# and exposes it through /usr/local/bin/hermes.

set -euo pipefail

export DEBIAN_FRONTEND=noninteractive

HERMES_HOME="${HERMES_HOME:-/root/.hermes}"
export HERMES_HOME

echo "Installing Hermes Agent prerequisites..."
apt-get update
apt-get install -y ca-certificates curl git gnupg lsb-release sudo

echo "Running the official Hermes Agent installer..."
curl -fsSL https://hermes-agent.nousresearch.com/install.sh -o /tmp/hermes-install.sh
chmod +x /tmp/hermes-install.sh
bash /tmp/hermes-install.sh
rm -f /tmp/hermes-install.sh

echo "Locating the Hermes launcher..."
HERMES_BIN=""
for candidate in \
  "${HERMES_HOME}/hermes-agent/.hermes/bin/hermes" \
  "${HOME:-/root}/.local/bin/hermes" \
  /root/.local/bin/hermes
do
  if [ -x "${candidate}" ]; then
    HERMES_BIN="${candidate}"
    break
  fi
done

if [ -z "${HERMES_BIN}" ]; then
  echo "Hermes launcher was not found after installation." >&2
  echo "Searched under ${HERMES_HOME} and ~/.local/bin." >&2
  exit 1
fi

echo "Found launcher at ${HERMES_BIN}; linking it into /usr/local/bin..."
ln -sfn "${HERMES_BIN}" /usr/local/bin/hermes

echo "Creating Hermes helper documentation..."
mkdir -p /opt/hermes
cat > /opt/hermes/README << 'EOF'
Hermes Agent is installed under /root/.hermes and exposed to every shell
through the /usr/local/bin/hermes symlink. Run it as root.

The first interactive root login automatically starts the configuration
wizard (`hermes setup --portal`) via /etc/profile.d/hermes-first-login.sh.
It is offered again on every login until it completes successfully.
Set HERMES_SKIP_FIRST_LOGIN=1 to log in without being prompted, or run
`touch /var/lib/hermes/first-login.done` to disable it permanently.

Per-instance preparation runs once through hermes-firstboot.service, which
stands in for the cloud-init hook this base image cannot provide.

Quick start:
  hermes setup --portal
  hermes

Manual provider setup:
  hermes model
  hermes tools
  hermes gateway setup

Diagnostics:
  hermes doctor

Documentation:
  https://hermes-agent.nousresearch.com/docs/getting-started/installation
EOF

echo "Arming the first-login setup wizard..."
for f in \
  /opt/hermes/first-login.sh \
  /opt/hermes/first-boot.sh \
  /etc/profile.d/hermes-first-login.sh \
  /etc/systemd/system/hermes-firstboot.service
do
  if [ ! -f "${f}" ]; then
    echo "Missing required file: ${f}" >&2
    exit 1
  fi
done
chmod 0755 /opt/hermes/first-login.sh /opt/hermes/first-boot.sh
# Sourced by /etc/profile, so it only needs to be readable.
chmod 0644 /etc/profile.d/hermes-first-login.sh
chmod 0644 /etc/systemd/system/hermes-firstboot.service
mkdir -p /var/lib/hermes
# The markers must never be baked into the snapshot, otherwise no customer ever
# sees the wizard.
rm -f /var/lib/hermes/first-login.done /var/lib/hermes/first-boot.done

echo "Enabling hermes-firstboot.service..."
# This replaces the cloud-init per-instance hook, which never runs: the
# ubuntu-26.04-x86_64 base image ships without cloud-init.
systemctl daemon-reload
systemctl enable hermes-firstboot.service

echo "Validating Hermes Agent command..."
# Resolved through /usr/local/bin, which is on the default PATH of both the
# non-interactive build shell and cloud-init.
if ! /usr/local/bin/hermes --help >/dev/null 2>&1; then
  echo "The Hermes launcher at ${HERMES_BIN} did not run successfully." >&2
  exit 1
fi

echo "Hermes Agent installation completed successfully!"
echo "'hermes setup --portal' runs automatically on the first interactive root login."
