#!/bin/sh

curl -fsSL "https://www.mongodb.org/static/pgp/server-${repo_version}.asc" | gpg --dearmor -o /etc/apt/trusted.gpg.d/mongodb.gpg

distro="$(lsb_release -s -c)"
echo "deb [ arch=amd64,arm64 ] https://repo.mongodb.org/apt/ubuntu ${distro}/mongodb-org/${repo_version} multiverse" | sudo tee /etc/apt/sources.list.d/mongodb.list

apt -qqy update
apt -qqy install mongodb-org=${mongodb_version} mongodb-org-mongos=${mongodb_version} mongodb-org-server=${mongodb_version} mongodb-org-shell=${mongodb_version} mongodb-org-tools=${mongodb_version}
