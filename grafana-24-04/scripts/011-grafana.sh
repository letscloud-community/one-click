#!/bin/sh

curl -fsSL https://apt.grafana.com/gpg.key | gpg --dearmor -o /etc/apt/trusted.gpg.d/grafana.gpg

cat > /etc/apt/sources.list.d/grafana.list <<EOM
deb [arch=amd64] https://apt.grafana.com stable main
EOM

apt-get -y update
apt-get -y install grafana

systemctl daemon-reload
systemctl enable grafana-server
systemctl start grafana-server
