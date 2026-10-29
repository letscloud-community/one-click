packer {
  required_plugins {
    letscloud = {
      version = ">= 0.1.1"
      source  = "github.com/letscloud-community/letscloud"
    }
  }
}

variable "api_key" {
  type = string
}

source "letscloud" "dragonwilds" {
  api_key       = var.api_key
  location_slug = "sao2"
  plan_slug     = "2vcpu-4gb-80ssd"
  image_slug    = "ubuntu-24.04-x86_64"
  snapshot_name = "dragonwilds-24-04"
  ssh_username  = "root"
}

build {
  sources = ["source.letscloud.dragonwilds"]

  provisioner "shell" {
    inline = [
      "cloud-init status --wait"
    ]
  }

  # Preparation only. No package is upgraded here, so the SSH session survives.
  provisioner "shell" {
    environment_vars = [
      "DEBIAN_FRONTEND=noninteractive",
      "NEEDRESTART_SUSPEND=1",
      "NEEDRESTART_MODE=l",
      "LC_ALL=C",
      "LANG=en_US.UTF-8",
      "LC_CTYPE=en_US.UTF-8"
    ]
    inline = [
      "cloud-init status --wait || true",
      "systemctl stop unattended-upgrades.service >/dev/null 2>&1 || true",
      "systemctl disable unattended-upgrades.service >/dev/null 2>&1 || true",
      # needrestart bounces sshd and networking while packages are unpacked,
      # which is what drops Packer. Disable it for the whole build; the reboot
      # below applies everything at once instead.
      "mkdir -p /etc/needrestart/conf.d",
      "echo \"\\$nrconf{restart} = 'l';\" > /etc/needrestart/conf.d/99-packer.conf",
      "echo \"\\$nrconf{kernelhints} = -1;\" >> /etc/needrestart/conf.d/99-packer.conf",
      "while fuser /var/lib/dpkg/lock-frontend /var/lib/apt/lists/lock /var/cache/apt/archives/lock >/dev/null 2>&1; do echo 'Waiting for apt lock...'; sleep 5; done",
      "sed -i 's|http://[^ ]*ubuntu.com/ubuntu/|http://archive.ubuntu.com/ubuntu/|g' /etc/apt/sources.list.d/ubuntu.sources",
      "apt -qqy update"
    ]
  }

  # Full system upgrade, detached from the SSH session. A disconnect here is
  # expected and harmless: the job keeps running on the box and the provisioner
  # below reconnects and waits for the same marker file.
  provisioner "shell" {
    expect_disconnect = true
    environment_vars = [
      "DEBIAN_FRONTEND=noninteractive",
      "NEEDRESTART_SUSPEND=1",
      "NEEDRESTART_MODE=l",
      "LC_ALL=C",
      "LANG=en_US.UTF-8",
      "LC_CTYPE=en_US.UTF-8"
    ]
    scripts = [
      "./scripts/005-system-upgrade.sh"
    ]
  }

  # Keep waiting for the same marker. While apt runs, sshd and dbus restart
  # several times and the session can drop more than once, so every disconnect
  # up to the final reboot has to be tolerated.
  provisioner "shell" {
    expect_disconnect   = true
    pause_before        = "30s"
    start_retry_timeout = "30m"
    inline = [
      "for i in $(seq 1 240); do if [ -f /var/lib/packer-upgrade.done ]; then echo 'Upgrade finished; the box is about to reboot.'; break; fi; if [ $((i % 6)) -eq 0 ]; then echo \"Still waiting for the detached upgrade... ($((i / 6)) min)\"; fi; sleep 10; done"
    ]
  }

  # The box has rebooted by now, so nothing restarts sshd any more. Confirm the
  # upgrade really finished, heal anything dpkg left pending and install the
  # build dependencies.
  provisioner "shell" {
    pause_before        = "60s"
    start_retry_timeout = "30m"
    environment_vars = [
      "DEBIAN_FRONTEND=noninteractive",
      "NEEDRESTART_SUSPEND=1",
      "NEEDRESTART_MODE=l",
      "LC_ALL=C",
      "LANG=en_US.UTF-8",
      "LC_CTYPE=en_US.UTF-8"
    ]
    inline = [
      "cloud-init status --wait || true",
      "for i in $(seq 1 120); do if [ -f /var/lib/packer-upgrade.done ]; then break; fi; echo 'Waiting for the detached upgrade...'; sleep 10; done",
      "test -f /var/lib/packer-upgrade.done || { echo 'ERROR: upgrade did not finish in time'; tail -n 40 /var/log/packer-upgrade.log 2>/dev/null; exit 1; }",
      "echo \"Detached upgrade exit code: $(cat /var/lib/packer-upgrade.done)\"",
      "uptime",
      "while fuser /var/lib/dpkg/lock-frontend /var/lib/apt/lists/lock /var/cache/apt/archives/lock >/dev/null 2>&1; do echo 'Waiting for apt lock...'; sleep 5; done",
      "dpkg --configure -a || true",
      "apt-get -qqy -f install || true",
      # Fail fast rather than letting a partially upgraded system reach the
      # snapshot. Anything still pending here would otherwise be upgraded by a
      # later provisioner, restarting sshd and dropping the session.
      "apt-get update -y >/dev/null 2>&1 || true",
      # $$ escapes the HCL interpolation so the shell receives a literal $.
      "PENDING=$(apt-get -s upgrade 2>/dev/null | grep -c '^Inst ' || true); echo \"Packages still pending: $${PENDING}\"; if [ \"$${PENDING}\" -gt 0 ]; then echo 'ERROR: the system is not fully upgraded. Last lines of the upgrade log:'; tail -n 30 /var/log/packer-upgrade.log 2>/dev/null; exit 1; fi",
      "apt -qqy -o Dpkg::Options::='--force-confdef' -o Dpkg::Options::='--force-confold' install software-properties-common curl wget jq openssl ufw ca-certificates gnupg lsb-release conntrack",
      "apt-get -qqy clean"
    ]
  }

  # Uploaded only after the reboot, so that a cloud-init run triggered by the
  # reboot can never execute the first boot script that is staged below.
  provisioner "file" {
    source      = "./files/etc/"
    destination = "/etc/"
  }

  provisioner "file" {
    source      = "./files/opt/"
    destination = "/opt/"
  }

  provisioner "file" {
    source      = "./files/var/"
    destination = "/var/"
  }

  provisioner "shell" {
    environment_vars = [
      "DEBIAN_FRONTEND=noninteractive",
      "NEEDRESTART_SUSPEND=1",
      "NEEDRESTART_MODE=l",
      "LC_ALL=C",
      "LANG=en_US.UTF-8",
      "LC_CTYPE=en_US.UTF-8"
    ]
    scripts = [
      "./scripts/011-dragonwilds.sh",
      "../common-scripts/018-force-ssh.sh",
      # Local cleanup rather than the shared one: the shared script ends with an
      # unbounded zerofill that fills the 80 GB disk and drops the SSH session.
      "./scripts/900-cleanup.sh"
    ]
  }

  post-processor "shell-local" {
    inline = [
      "echo 'RuneScape: Dragonwilds image built successfully!'",
      "echo 'Deploy the snapshot, then run /opt/dragonwilds/scripts/first-boot.sh with your Owner ID.'"
    ]
  }
}
