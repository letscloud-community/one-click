#!/bin/sh

curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/trusted.gpg.d/docker.gpg

cat > /etc/apt/sources.list.d/docker.list <<EOM
deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -c -s) stable
EOM

apt-get -y update
apt-get -y install docker-ce

systemctl enable docker
systemctl start docker
