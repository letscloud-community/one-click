#!/bin/sh

##############################
## PART: install NodeJS:
##
## vi: syntax=sh expandtab ts=4

curl -fsSL "https://deb.nodesource.com/setup_${NODE_VERSION}" | sudo -E bash -

# Yarn
curl -fsSL https://dl.yarnpkg.com/debian/pubkey.gpg | gpg --dearmor -o /etc/apt/trusted.gpg.d/pubkey.gpg
echo "deb https://dl.yarnpkg.com/debian/ stable main" | sudo tee /etc/apt/sources.list.d/yarn.list

sudo apt -qqy update
sudo apt -qqy install nodejs yarn

node -v
npm -v
yarn -v
