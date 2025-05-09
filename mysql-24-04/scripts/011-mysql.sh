#!/bin/sh

# Clone and install mytop
git clone https://github.com/jzawodn/mytop.git /tmp/mytop
cd /tmp/mytop || exit 1
sudo perl Makefile.PL
make
sudo make install

# Clean up
cd ~
rm -rf /tmp/mytop

# Create ~/.mytop config
cat <<EOF > ~/.mytop
user=root
host=localhost
db=mysql
delay=5
port=3306
EOF

chmod 600 ~/.mytop