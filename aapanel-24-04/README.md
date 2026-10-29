# aaPanel 24.04 - One-Click Deployment

This project provides a pre-configured Ubuntu 24.04 image with aaPanel 8.0.3 (Free Edition) installed and ready to use.

## What is aaPanel?

aaPanel is a free, powerful, and easy-to-use Linux control panel that has been installed and approved by over 12 million servers worldwide. It provides a web-based interface for managing:

- Web servers (Nginx, Apache, OpenLiteSpeed)
- Databases (MySQL, MariaDB, PostgreSQL, MongoDB)
- PHP (multiple versions 5.3-8.5)
- FTP servers
- SSL certificates (automatic trusted IP certificates)
- Docker management
- File management
- And much more!

## Features

- **aaPanel 8.0.3** (Free Edition)
- **Ubuntu 24.04 LTS** base system
- **Automatic SSL certificates** for panel and websites (ipssl enabled)
- **Nginx** web server
- **MySQL** database
- **PHP** (multiple versions)
- **Redis** cache
- **Memcached**
- **FTP server**
- **Firewall** configured
- **Docker** support ready

## Quick Start

### 1. Build the Image

```bash
cd aapanel-24-04
packer build -var="api_key=YOUR_LETSCLOUD_API_KEY" aapanel-24-04.pkr.hcl
```

### 2. Deploy the Instance

After building, you can deploy the snapshot to create aaPanel instances on LetsCloud.

### 3. Access aaPanel

Once deployed, access aaPanel at:
- **URL**: `http://your-server-ip:8888` (or `https://` if SSL is configured)
- **Username**: Run `bt default` on the server to see the default username
- **Password**: Run `bt default` on the server to see the default password

**Note**: With `ipssl` enabled, aaPanel will automatically configure trusted IP certificates for both the panel and your websites.

## Default Configuration

### Ports
- **aaPanel**: 8888 (configurable)
- **HTTP**: 80
- **HTTPS**: 443
- **SSH**: 22

### Services
All services are automatically started and configured:
- aaPanel control panel
- Nginx web server
- MySQL database
- PHP-FPM
- Redis cache
- Memcached
- FTP server

## Management Commands

### aaPanel Management
```bash
bt                    # aaPanel management tool
bt default           # Show default login info
bt restart           # Restart aaPanel
bt stop              # Stop aaPanel
bt start             # Start aaPanel
```

### Service Management
```bash
aapanel-manage status    # Check all services status
aapanel-manage restart   # Restart aaPanel
aapanel-manage stop      # Stop aaPanel
aapanel-manage start     # Start aaPanel
aapanel-manage info      # Show login information
```

### Individual Services
```bash
systemctl status nginx      # Nginx status
systemctl status mysql      # MySQL status
systemctl status php-fpm    # PHP-FPM status
systemctl status redis      # Redis status
systemctl status memcached  # Memcached status
```

## Security

### Firewall
The firewall is configured with the following rules:
- Port 22 (SSH)
- Port 80 (HTTP)
- Port 443 (HTTPS)
- Port 8888 (aaPanel - configurable)

### Default Security
- Change default passwords after first login
- Configure SSL certificates
- Set up proper user permissions
- Regular security updates

## Customization

### Change aaPanel Port
```bash
echo '8881' > /www/server/panel/data/port.pl
bt restart
ufw allow 8881/tcp
```

### Change Panel Password
```bash
bt default
# Or manually:
cd /www/server/panel && python tools.py panel your_new_password
```

### Change MySQL Root Password
```bash
cd /www/server/panel && python tools.py root your_new_password
```

## File Locations

### aaPanel
- **Installation**: `/www/server/panel`
- **Websites**: `/www/wwwroot`
- **Logs**: `/www/wwwlogs`
- **Backups**: `/www/backup`

### Configuration Files
- **Nginx**: `/www/server/nginx/conf/nginx.conf`
- **MySQL**: `/etc/my.cnf`
- **PHP**: `/www/server/php/*/etc/php.ini`

## Troubleshooting

### Check Service Status
```bash
aapanel-manage status
```

### View Logs
```bash
# aaPanel logs
cat /tmp/panelBoot

# Nginx logs
tail -f /www/wwwlogs/access.log
tail -f /www/wwwlogs/error.log

# MySQL logs
cat /www/server/data/*.err
```

### Restart Services
```bash
# Restart aaPanel
bt restart

# Restart all services
systemctl restart nginx mysql redis memcached
```

## Documentation

- **Official aaPanel**: https://www.aapanel.com
- **aaPanel Documentation**: https://www.aapanel.com/docs
- **Community Forum**: https://forum.aapanel.com

## Support

For issues related to:
- **aaPanel**: Visit https://forum.aapanel.com
- **This Image**: Check the logs and documentation above

## License

This project is licensed under the same terms as aaPanel (Free Edition).

---

**Note**: This is a pre-configured image for quick deployment. Always change default passwords and configure security settings after deployment.
