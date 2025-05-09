#!/bin/sh

curl -fsSL https://packages.gitlab.com/install/repositories/gitlab/gitlab-ce/script.deb.sh | sudo bash

apt -y update
apt -y install gitlab-ce

GITLAB_ROOT_PASSWORD='letscloud'
gitlab-ctl reconfigure