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

variable "apt_packages" {
  type    = string
  default = "ca-certificates curl git gnupg lsb-release sudo software-properties-common"
}

source "letscloud" "hermes" {
  api_key       = var.api_key
  location_slug = "sao2"
  plan_slug     = "1vcpu-2gb-50ssd"
  image_slug    = "ubuntu-26.04-x86_64"
  snapshot_name = "hermes-26-04"
  ssh_username  = "root"
}

build {
  sources = ["source.letscloud.hermes"]

  provisioner "shell" {
    inline = [
      "if command -v cloud-init >/dev/null 2>&1; then cloud-init status --wait; else echo 'cloud-init not found; continuing'; fi"
    ]
  }

  provisioner "file" {
    source      = "./files/etc/"
    destination = "/etc/"
  }

  provisioner "file" {
    source      = "./files/opt/"
    destination = "/opt/"
  }

  provisioner "shell" {
    environment_vars = [
      "DEBIAN_FRONTEND=noninteractive",
      "LC_ALL=C",
      "LANG=en_US.UTF-8",
      "LC_CTYPE=en_US.UTF-8"
    ]
    inline = [
      "sed -i 's|http://[^ ]*ubuntu.com/ubuntu/|http://archive.ubuntu.com/ubuntu/|g' /etc/apt/sources.list.d/ubuntu.sources",
      "apt -qqy update",
      "apt -qqy -o Dpkg::Options::='--force-confdef' -o Dpkg::Options::='--force-confold' full-upgrade",
      "apt -qqy -o Dpkg::Options::='--force-confdef' -o Dpkg::Options::='--force-confold' install ${var.apt_packages}",
      "apt-get -qqy clean"
    ]
  }

  provisioner "shell" {
    environment_vars = [
      "DEBIAN_FRONTEND=noninteractive",
      "LC_ALL=C",
      "LANG=en_US.UTF-8",
      "LC_CTYPE=en_US.UTF-8"
    ]
    scripts = [
      "./scripts/011-hermes.sh",
      # common-scripts/018-force-ssh.sh is deliberately NOT used here. It adds a
      # `Match User root` / ForceCommand guard that every other image removes
      # from its cloud-init per-instance hook, but the ubuntu-26.04-x86_64 base
      # ships without cloud-init, so nothing would ever remove it and root would
      # be locked out of the deployed instance. Nothing has to be waited for on
      # first boot either: the agent is fully installed at build time.
      #
      # Local cleanup rather than the shared one: the shared script ends with an
      # unbounded zerofill that fills the disk and drops the SSH session.
      "./scripts/900-cleanup.sh"
    ]
  }

  post-processor "shell-local" {
    inline = [
      "echo 'Hermes Agent image built successfully!'",
      "echo 'You can now deploy this snapshot to create Hermes Agent instances'"
    ]
  }
}
