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

source "letscloud" "n8n" {
  api_key       = var.api_key
  location_slug = "sao2"
  plan_slug     = "1vcpu-2gb-20ssd"
  image_slug    = "ubuntu-24.04-x86_64"
  snapshot_name = "n8n-24-04"
  ssh_username  = "root"
}

build {
  sources = ["source.letscloud.n8n"]

  provisioner "shell" {
    inline = [
      "cloud-init status --wait"
    ]
  }

  provisioner "file" {
    source      = "./files/etc/"
    destination = "/etc/"
  }

  provisioner "file" {
    source      = "./files/var/"
    destination = "/var/"
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
      "apt -qqy -o Dpkg::Options::='--force-confdef' -o Dpkg::Options::='--force-confold' install software-properties-common",
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
      "./scripts/011-n8n.sh",
      "../common-scripts/018-force-ssh.sh",
      "../common-scripts/900-cleanup.sh"
    ]
  }

  post-processor "shell-local" {
    inline = [
      "echo 'n8n image built successfully!'",
      "echo 'You can now deploy this snapshot to create n8n instances'"
    ]
  }
}
