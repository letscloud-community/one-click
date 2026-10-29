# Offers the RuneScape: Dragonwilds setup wizard on the first interactive login.
#
# This file ships inside the image and is sourced by /etc/profile for every
# login shell, which makes the wizard appear even if cloud-init never ran the
# per-instance script. Relying on a line appended to /root/.bashrc at first
# boot proved unreliable, because a single failure in that boot stage left the
# customer with no prompt at all.
#
# It is SOURCED, never executed, so it must not call exit and must not fail.

# Interactive shells only.
case $- in
  *i*) ;;
  *) return 0 2>/dev/null || true ;;
esac

if [ -n "${BASH_VERSION:-}" ] || [ -n "${KSH_VERSION:-}" ] || [ -n "${ZSH_VERSION:-}" ]; then
  # Only root can configure the server.
  if [ "$(id -u)" = "0" ] \
     && [ -t 0 ] \
     && [ -x /opt/dragonwilds/scripts/first-boot.sh ] \
     && [ ! -f /var/lib/dragonwilds/first-boot.done ] \
     && [ -z "${DW_SKIP_FIRST_BOOT:-}" ]; then
    # The wizard writes its own marker on success, so it never runs twice.
    # Set DW_SKIP_FIRST_BOOT=1 to log in without being prompted.
    /opt/dragonwilds/scripts/first-boot.sh || true
  fi
fi
