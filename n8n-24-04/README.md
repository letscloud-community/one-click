# n8n on Ubuntu 24.04 (LetsCloud one-click)

Builds a LetsCloud snapshot that boots a production-shaped [n8n](https://n8n.io)
instance: n8n 2.x behind nginx, backed by PostgreSQL, with Code node execution
isolated in external task runners.

## Architecture

```
Internet :80  ->  nginx (host service)  ->  127.0.0.1:5678
                                                 |
                      Docker Compose project "n8n" (/opt/n8n)
                                                 |
                      +--------------+-----------+-------------+
                      | n8n          | postgres  | runners     |
                      | application  | database  | Code node   |
                      |              |           | isolation   |
                      +--------------+-----------+-------------+
                            network: n8n_internal (no published ports
                            except n8n on 127.0.0.1:5678)
```

| Component | Image | Notes |
| --- | --- | --- |
| n8n | `docker.io/n8nio/n8n` | Reachable only through nginx |
| PostgreSQL | `postgres:18` | `PGDATA` pinned so the volume survives major upgrades |
| Task runners | `docker.io/n8nio/runners` | External mode; internal mode is removed in n8n 3.0 |
| nginx | Ubuntu package | Reverse proxy on port 80 |

Both n8n images share `N8N_IMAGE_TAG` because upstream requires their versions
to match.

## Build

```bash
packer init .
packer build -var api_key=$LETSCLOUD_API_KEY .
```

The build installs and configures everything but **never starts the stack**.
Starting n8n during the build would write a credential encryption key and a
PostgreSQL cluster into the snapshot, and every instance created from it would
then share the same secrets.

## First boot

`n8n-init.service` runs once, before `n8n.service`, and:

1. generates a unique `N8N_ENCRYPTION_KEY`, `POSTGRES_PASSWORD` and
   `N8N_RUNNERS_AUTH_TOKEN`;
2. detects the server's public IP and sets `N8N_WEBHOOK_URL`;
3. copies the host timezone into `GENERIC_TIMEZONE`;
4. adds a 1 GB swapfile on instances with less than 4 GB of RAM;
5. writes `/opt/n8n/.env` (mode `0600`) and `/root/.n8n_credentials`.

`n8n.service` then brings up the Compose stack. Container images are pre-pulled
during the build, so the instance is usually ready within a minute.

n8n has **no default login**. Open `http://<server-ip>/` and complete the setup
wizard; the first account you create owns the instance.

## Operating the instance

| Task | Command |
| --- | --- |
| Status | `systemctl status n8n` |
| Restart | `systemctl restart n8n` |
| Logs (service) | `journalctl -u n8n -f` |
| Logs (containers) | `n8n-compose --env-file /opt/n8n/.env -f /opt/n8n/docker-compose.yml logs -f n8n` |
| Container status | `n8n-compose --env-file /opt/n8n/.env -f /opt/n8n/docker-compose.yml ps` |
| Database shell | `n8n-compose --env-file /opt/n8n/.env -f /opt/n8n/docker-compose.yml exec postgres psql -U n8n -d n8n` |
| Upgrade | `/opt/n8n/update.sh` |

Apply any change to `/opt/n8n/.env` with `systemctl restart n8n`.

### Files

| Path | Purpose |
| --- | --- |
| `/opt/n8n/.env` | Live configuration and secrets (`0600`) |
| `/opt/n8n/.env.example` | Reference copy of every supported variable |
| `/opt/n8n/docker-compose.yml` | Stack definition |
| `/opt/n8n/n8n-init.sh` | First-boot initialization |
| `/opt/n8n/update.sh` | Pull new images and restart |
| `/opt/n8n/files` | Host-side `~/.n8n-files`, the only directory the file nodes may access |
| `/etc/nginx/conf.d/n8n.conf` | Reverse proxy vhost |
| `/root/.n8n_credentials` | Generated secrets, for reference |

## Using your own domain with HTTPS

```bash
# 1. Point your domain's DNS A record at the server, then:
sudo apt-get install -y python3-certbot-nginx
sudo certbot --nginx -d your-domain.com

# 2. Tell n8n its public URL:
sudo sed -i 's|^N8N_HOSTNAME=.*|N8N_HOSTNAME=your-domain.com|' /opt/n8n/.env
sudo sed -i 's|^N8N_PROTOCOL=.*|N8N_PROTOCOL=https|' /opt/n8n/.env
sudo sed -i 's|^N8N_WEBHOOK_URL=.*|N8N_WEBHOOK_URL=https://your-domain.com/|' /opt/n8n/.env
sudo sed -i 's|^N8N_SECURE_COOKIE=.*|N8N_SECURE_COOKIE=true|' /opt/n8n/.env
sudo systemctl restart n8n
```

`N8N_WEBHOOK_URL` is what n8n registers with external services and shows in the
editor, so it must always match the URL users and webhook callers actually hit.

## Upgrades

`N8N_IMAGE_TAG` defaults to `latest`, which can cross a major version.
For predictable upgrades, pin a version:

```bash
sudo sed -i 's|^N8N_IMAGE_TAG=.*|N8N_IMAGE_TAG=2.45.4|' /opt/n8n/.env
sudo /opt/n8n/update.sh
```

Review the [release notes](https://docs.n8n.io/changelog/release-notes/) and the
[breaking changes](https://docs.n8n.io/changelog/v30-breaking-changes.md) before
a major bump.

> **Back up `N8N_ENCRYPTION_KEY`.** Every stored credential is encrypted with
> it. Without that key the credentials cannot be recovered, even from a database
> backup.

## Configuration notes

`/opt/n8n/.env` pins four settings whose upstream defaults are scheduled to
change, so that an upgrade never silently alters instance behaviour:

| Variable | Value | Why |
| --- | --- | --- |
| `N8N_UNVERIFIED_PACKAGES_ENABLED` | `true` | Keeps community nodes installable. Set to `false` to allow verified nodes only. |
| `N8N_RUNNERS_TASK_TIMEOUT` | `300` | Upstream will lower the default to `60` seconds. |
| `N8N_COMPRESSION_NODE_MAX_DECOMPRESSED_SIZE_BYTES` | `268435456` | 256 MiB instead of 2 GiB, sized for the smaller plans. |
| `N8N_COMPRESSION_NODE_MAX_ZIP_ENTRIES` | `1000` | Matches the announced future default. |

The stack also hardens a few defaults: diagnostics/telemetry are off, the
PostgreSQL port and the task broker port are never published to the host, and
Prometheus metrics stay disabled (enabling `N8N_METRICS` would expose
`/metrics` through nginx without authentication).

## References

- [n8n documentation](https://docs.n8n.io)
- [Install using Docker Compose](https://docs.n8n.io/deploy/host-n8n/install-options/install-using-docker-compose.md)
- [Set up task runners](https://docs.n8n.io/deploy/host-n8n/configure-n8n/set-up-task-runners.md)
- [Configure webhook URLs with reverse proxy](https://docs.n8n.io/deploy/host-n8n/configure-n8n/basic-configuration/configuration-examples/configure-webhook-urls-with-reverse-proxy.md)
