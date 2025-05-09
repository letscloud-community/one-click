packer {
  required_plugins {
    letscloud = {
      version = ">= 0.1.1"
      source  = "github.com/letscloud-community/letscloud"
    }
  }
}

variable "api_key" {
  type    = string
}

variable "apt_packages" {
  type    = string
  default = "apt-transport-https ca-certificates curl software-properties-common postfix tzdata perl"
}

source "letscloud" "one-click" {
  api_key              = var.api_key
  location_slug        = "mia1"
  plan_slug            = "2vcpu-4gb-30ssd"
  image_slug           = "ubuntu-24.04-x86_64"
  snapshot_name        = "gitlab-ce-24-04"
}

build {
  sources = ["source.letscloud.one-click"]

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
      "./scripts/011-gitlab.sh",
      "../common-scripts/018-force-ssh.sh",
      "../common-scripts/900-cleanup.sh"
    ]
  }

}
