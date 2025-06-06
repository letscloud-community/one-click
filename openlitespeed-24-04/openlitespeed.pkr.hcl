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

variable "admin_password" {
  type    = string
  default = "letscloud_change_pass"
  description = "Password for OpenLiteSpeed WebAdmin interface"
}

variable "admin_email" {
  type    = string
  default = "admin@example.com"
  description = "Administrator email for OpenLiteSpeed"
}

variable "apt_packages" {
  type    = string
  default = "wget curl software-properties-common git unzip"
}

source "letscloud" "one-click" {
  api_key              = var.api_key
  location_slug        = "mia1"
  plan_slug            = "1vcpu-2gb-20ssd"
  image_slug           = "ubuntu-24.04-x86_64"
  snapshot_name        = "openlitespeed-24-04"
}

build {
  sources = ["source.letscloud.one-click"]

  provisioner "shell" {
    inline = [
      "cloud-init status --wait"
    ]
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
      "LC_CTYPE=en_US.UTF-8",
      "admin_password=${var.admin_password}",
      "admin_email=${var.admin_email}"
    ]
    inline = [
      # Install OpenLiteSpeed using the official one-click script
      "curl -k https://raw.githubusercontent.com/litespeedtech/ols1clk/master/ols1clk.sh -o ols1clk.sh",
      "chmod +x ols1clk.sh",
      "./ols1clk.sh --quiet --lsphp 81 --adminpassword \"${var.admin_password}\" --email \"${var.admin_email}\""
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
      "admin_password=${var.admin_password}"
    ]
    scripts = [
      "../common-scripts/018-force-ssh.sh",
      "../common-scripts/900-cleanup.sh"
    ]
  }
}
