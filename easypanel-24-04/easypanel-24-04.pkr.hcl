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
  default = "apt-transport-https ca-certificates curl jq linux-image-extra-virtual software-properties-common"
}

variable "docker_compose_version" {
  type    = string
  default = ""
}

source "letscloud" "one-click" {
  api_key              = var.api_key
  location_slug        = "sao2"
  plan_slug            = "1vcpu-2gb-20ssd"
  image_slug           = "ubuntu-24.04-x86_64"
  snapshot_name        = "easypanel-24-04"
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
      "docker_compose_version=${var.docker_compose_version}",
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
      "../common-scripts/010-docker.sh",
      "../common-scripts/011-docker-compose.sh",
      "../common-scripts/012-grub-opts.sh",
      "../common-scripts/013-docker-dns.sh",
      "./scripts/011-easypanel.sh",
      "../common-scripts/900-cleanup.sh"
    ]
  }

}
