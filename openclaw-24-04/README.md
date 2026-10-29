# OpenClaw One-Click

One-click image with [OpenClaw](https://openclaw.ai) pre-installed. OpenClaw is an open agent platform that runs on your machine and works from the chat apps you already use—WhatsApp, Telegram, Discord, Slack, Teams. Your assistant. Your machine. Your rules.

## What's Included

- **Ubuntu 24.04**
- **Node.js 24 LTS (24.22.1+)**
- **OpenClaw CLI** (installed via official script)
- **Gateway token** auto-generated on first boot
- **Helper scripts** for status, restart, and update

## After Creating the Instance

1. Wait for the first boot and connect via SSH:
   ```bash
   ssh root@YOUR_IP
   ```

2. The Gateway starts automatically. Get the token:
   ```bash
   cat /opt/openclaw/gateway-token.txt
   ```

3. Access the Control UI. HTTPS is enabled on first boot. Run `cat /opt/openclaw/control-ui-url.txt` to get the URL with token, or see [Gateway Access](#gateway-access) for all options.

4. Configure API keys and channels (optional):
   ```bash
   openclaw onboard --install-daemon
   ```

## Gateway Access

The Gateway is available immediately after first boot. **HTTPS is enabled automatically** with a self-signed certificate. Browsers require HTTPS or localhost. Three access options:

### Option 1 – HTTPS by IP (automatic on first boot)

HTTPS with self-signed certificate is configured automatically. Get the **tokenized URL** (includes token, no manual paste):

```bash
cat /opt/openclaw/control-ui-url.txt
```

Copy the URL and open it in your browser. Accept the certificate warning (Advanced → Proceed). The token in the URL authenticates automatically.

**First remote connection:** If you see "pairing required", approve your device once from SSH:
```bash
openclaw devices list
openclaw devices approve REQUEST_ID
```
Then refresh the Control UI page.

### Option 2 – HTTPS by domain (Let's Encrypt)

For production use with a custom domain. Requires DNS pointing to your server.

```bash
sudo /opt/setup-https-openclaw.sh your-domain.com
```

Then use the URL shown (or `https://your-domain.com/?token=TOKEN`).

### Option 3 – SSH tunnel (localhost)

Forward the port via SSH and access as localhost.

```bash
ssh -L 18789:localhost:18789 root@YOUR_IP
```

Then open **http://localhost:18789/** in your browser. Paste the token when prompted.

---

**Token:** `cat /opt/openclaw/gateway-token.txt` | **URL with token:** `cat /opt/openclaw/control-ui-url.txt`

> Ensure port 443 is open in your cloud firewall for HTTPS access.

## Helper Scripts

| Script | Description |
|--------|-------------|
| `/opt/status-openclaw.sh` | Show status, token, and Gateway URL |
| `/opt/restart-openclaw.sh` | Restart the Gateway |
| `/opt/update-openclaw.sh` | Update OpenClaw to latest version |
| `/opt/setup-https-openclaw.sh [DOMAIN]` | Enable HTTPS by IP (no arg) or by domain (Let's Encrypt) |

## Useful Commands

| Command | Description |
|---------|-------------|
| `openclaw status --all` | Full system status (best debug report) |
| `openclaw gateway status` | Gateway status |
| `openclaw health` | Health diagnostics |
| `openclaw security audit --deep` | Security audit |
| `openclaw channels login` | WhatsApp login (QR code) |
| `openclaw pairing list whatsapp` | List pending pairings |
| `openclaw pairing approve whatsapp CODE` | Approve pairing |
| `openclaw devices list` | List pending device pairings (Control UI) |
| `openclaw devices approve REQUEST_ID` | Approve device (fix "pairing required") |
| `openclaw dashboard` | Open Control UI (local) |

## Configuration Files

- **Config**: `~/.openclaw/`
- **Workspace**: `~/.openclaw/workspace`
- **Credentials**: `~/.openclaw/credentials/`
- **Token**: `/opt/openclaw/gateway-token.txt`
- **URL with token**: `/opt/openclaw/control-ui-url.txt` (use this to access Control UI)

## Documentation

- [Getting started](https://docs.openclaw.ai/start/getting-started)
- [Wizard](https://docs.openclaw.ai/start/wizard)
- [Pairing](https://docs.openclaw.ai/start/pairing)
- [Security](https://docs.openclaw.ai/gateway/security)

## Troubleshooting

**"openclaw: command not found"**
```bash
export PATH="$(npm prefix -g)/bin:$PATH"
```

**Channels won't connect**
- Use a supported Node.js version: 24.22.1+ or 26.12.1+ (Bun has compatibility issues with WhatsApp/Telegram)

**Updating an existing instance**
The Node.js version is updated automatically only on newly built images. On an existing instance, update Node.js before updating OpenClaw:
```bash
curl -fsSL https://deb.nodesource.com/setup_24.x | bash -
apt-get update
apt-get install -y nodejs
node --version
/opt/update-openclaw.sh
```

**Gateway won't start**
```bash
openclaw health
openclaw status --all
```

**"pairing required" in Control UI**
```bash
openclaw devices list
openclaw devices approve REQUEST_ID
```

**HTTP 502 in the browser**
Caddy is up but the Gateway is not answering yet. The Gateway needs about 30 seconds to accept requests after a restart. Wait for it:
```bash
/usr/local/bin/openclaw-wait-ready 300 && echo ready
systemctl status openclaw --no-pager
```

**HTTP 403 `proxy_attribution_required`**
The Gateway does not trust the local reverse proxy. Re-apply the origin settings (`gateway.trustedProxies`, `gateway.publicOrigin`, `gateway.controlUi.allowedOrigins`) and restart:
```bash
/usr/local/bin/openclaw-set-origin https://YOUR_IP_OR_DOMAIN
systemctl restart openclaw
```

## Architecture

The Gateway listens on `127.0.0.1:18789` only; Caddy terminates HTTPS on port 443 and proxies to it, overwriting `X-Forwarded-For`/`X-Real-IP` so the Gateway can attribute the real client. Port 18789 is never exposed to the internet.

| File | Purpose |
|------|---------|
| `/usr/local/bin/openclaw-setup` | First-boot setup (token, config, HTTPS, readiness wait) |
| `/usr/local/bin/openclaw-start` | Gateway launcher used by `openclaw.service` |
| `/usr/local/bin/openclaw-set-origin` | Sets trusted proxy and browser origins in the config |
| `/usr/local/bin/openclaw-write-caddyfile` | Writes the Caddy reverse-proxy config |
| `/usr/local/bin/openclaw-wait-ready` | Blocks until the Gateway answers on loopback |
