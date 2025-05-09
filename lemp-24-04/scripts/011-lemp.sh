#!/bin/sh

rm -rvf /etc/nginx/sites-enabled/default

rm -rf /var/www/html/index*debian.html

chown -R www-data: /var/www

ln -s /etc/nginx/sites-available/letscloud \
      /etc/nginx/sites-enabled/letscloud
