#!/bin/bash

if [[ ! -d /tmp ]]; then
  mkdir /tmp
fi
chmod 1777 /tmp

apt-get -y update
apt-get -y upgrade
rm -rf /tmp/* /var/tmp/*
history -c
cat /dev/null > /root/.bash_history
unset HISTFILE
apt-get -y autoremove
apt-get -y autoclean
find /var/log -mtime -1 -type f -exec truncate -s 0 {} \;
rm -rf /var/log/*.gz /var/log/*.[0-9] /var/log/*-????????
rm -rf /var/lib/cloud/instances/*
rm -f /etc/cloud/cloud-init.disabled
rm -f /root/.ssh/authorized_keys /etc/ssh/*key*
touch /etc/ssh/revoked_keys
chmod 600 /etc/ssh/revoked_keys
rm -rf /etc/update-motd.d/50-landscape-sysinfo
rm -rf /etc/update-motd.d/85-fwupd
rm -rf /etc/update-motd.d/90-updates-available
rm -rf /etc/update-motd.d/91-release-upgrade
rm -rf /etc/update-motd.d/92-unattended-upgrades
rm -rf /etc/update-motd.d/95-hwe-eol
rm -rf /etc/update-motd.d/97-overlayroot
rm -rf /etc/update-motd.d/98-fsck-at-reboot
rm -rf /etc/update-motd.d/98-reboot-required

# Securely erase the unused portion of the filesystem
GREEN='\033[0;32m'
NC='\033[0m'
printf "\n${GREEN}Writing zeros to the remaining disk space to securely
erase the unused portion of the file system.
Depending on your disk size this may take several minutes.
The secure erase will complete successfully when you see:${NC}
    dd: writing to '/zerofile': No space left on device\n
Beginning secure erase now\n"

dd if=/dev/zero of=/zerofile &
  PID=$!
  while [ -d /proc/$PID ]
    do
      printf "."
      sleep 5
    done
sync; rm /zerofile; sync
cat /dev/null > /var/log/lastlog; cat /dev/null > /var/log/wtmp
