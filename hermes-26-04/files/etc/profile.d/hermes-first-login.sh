# Starts the Hermes Agent setup wizard on the first interactive root login.
#
# This file ships inside the image and is sourced by /etc/profile for every
# login shell, so the wizard is offered even if cloud-init never ran the
# per-instance script. Appending a line to /root/.bashrc at first boot would
# make the prompt depend on that boot stage succeeding.
#
# It is SOURCED, never executed, so it must not call exit and must not fail.

# Interactive shells only.
case $- in
  *i*) ;;
  *) return 0 2>/dev/null || true ;;
esac

if [ -n "${BASH_VERSION:-}" ] || [ -n "${KSH_VERSION:-}" ] || [ -n "${ZSH_VERSION:-}" ]; then
  # The agent is installed under /root, so only root can configure it.
  if [ "$(id -u)" = "0" ] \
     && [ -t 0 ] \
     && [ -x /opt/hermes/first-login.sh ] \
     && [ ! -f /var/lib/hermes/first-login.done ] \
     && [ -z "${HERMES_SKIP_FIRST_LOGIN:-}" ]; then
    # The wizard writes its own marker on success, so it never runs twice.
    # Set HERMES_SKIP_FIRST_LOGIN=1 to log in without being prompted.
    /opt/hermes/first-login.sh || true
  fi
fi
