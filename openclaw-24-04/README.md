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

---

# Português

Imagem one-click com [OpenClaw](https://openclaw.ai) pré-instalado. OpenClaw é uma plataforma de agentes abertos que roda na sua máquina e funciona nos apps de chat que você já usa—WhatsApp, Telegram, Discord, Slack, Teams. Seu assistente. Sua máquina. Suas regras.

## O que está incluído

- **Ubuntu 24.04**
- **Node.js 24 LTS (24.22.1+)**
- **OpenClaw CLI** (instalado via script oficial)
- **Token do Gateway** gerado automaticamente no primeiro boot
- **Scripts auxiliares** para status, reinício e atualização

## Após criar a instância

1. Aguarde o primeiro boot e conecte via SSH:
   ```bash
   ssh root@SEU_IP
   ```

2. O Gateway inicia automaticamente. Obtenha o token:
   ```bash
   cat /opt/openclaw/gateway-token.txt
   ```

3. Acesse a Control UI. O HTTPS é ativado no primeiro boot. Execute `cat /opt/openclaw/control-ui-url.txt` para obter a URL com token, ou veja [Acesso ao Gateway](#acesso-ao-gateway) para todas as opções.

4. Configure chaves de API e canais (opcional):
   ```bash
   openclaw onboard --install-daemon
   ```

## Acesso ao Gateway

O Gateway fica disponível logo após o primeiro boot. **HTTPS é ativado automaticamente** com certificado autoassinado. Navegadores exigem HTTPS ou localhost. Três opções de acesso:

### Opção 1 – HTTPS por IP (automático no primeiro boot)

HTTPS com certificado autoassinado é configurado automaticamente. Obtenha a **URL com token** (inclui o token, sem colar manualmente):

```bash
cat /opt/openclaw/control-ui-url.txt
```

Copie a URL e abra no navegador. Aceite o aviso de certificado (Avançado → Continuar). O token na URL autentica automaticamente.

**Primeira conexão remota:** Se aparecer "pairing required", aprove o dispositivo uma vez via SSH:
```bash
openclaw devices list
openclaw devices approve REQUEST_ID
```
Depois atualize a página da Control UI.

### Opção 2 – HTTPS por domínio (Let's Encrypt)

Para uso em produção com domínio próprio. Exige DNS apontando para o servidor.

```bash
sudo /opt/setup-https-openclaw.sh seu-dominio.com
```

Depois use a URL exibida (ou `https://seu-dominio.com/?token=TOKEN`).

### Opção 3 – Túnel SSH (localhost)

Encaminhe a porta via SSH e acesse como localhost.

```bash
ssh -L 18789:localhost:18789 root@SEU_IP
```

Depois abra **http://localhost:18789/** no navegador. Cole o token quando solicitado.

---

**Token:** `cat /opt/openclaw/gateway-token.txt` | **URL com token:** `cat /opt/openclaw/control-ui-url.txt`

> Libere a porta 443 no firewall da nuvem para acesso HTTPS.

## Scripts auxiliares

| Script | Descrição |
|--------|-----------|
| `/opt/status-openclaw.sh` | Mostra status, token e URL do Gateway |
| `/opt/restart-openclaw.sh` | Reinicia o Gateway |
| `/opt/update-openclaw.sh` | Atualiza o OpenClaw para a versão mais recente |
| `/opt/setup-https-openclaw.sh [DOMINIO]` | Ativa HTTPS por IP (sem arg) ou por domínio (Let's Encrypt) |

## Comandos úteis

| Comando | Descrição |
|---------|-----------|
| `openclaw status --all` | Status completo do sistema (melhor relatório de debug) |
| `openclaw gateway status` | Status do Gateway |
| `openclaw health` | Diagnóstico de saúde |
| `openclaw security audit --deep` | Auditoria de segurança |
| `openclaw channels login` | Login WhatsApp (QR code) |
| `openclaw pairing list whatsapp` | Listar pairings pendentes |
| `openclaw pairing approve whatsapp CODIGO` | Aprovar pairing |
| `openclaw devices list` | Listar dispositivos pendentes (Control UI) |
| `openclaw devices approve REQUEST_ID` | Aprovar dispositivo (corrige "pairing required") |
| `openclaw dashboard` | Abrir Control UI (local) |

## Arquivos de configuração

- **Config**: `~/.openclaw/`
- **Workspace**: `~/.openclaw/workspace`
- **Credenciais**: `~/.openclaw/credentials/`
- **Token**: `/opt/openclaw/gateway-token.txt`
- **URL com token**: `/opt/openclaw/control-ui-url.txt` (use para acessar a Control UI)

## Documentação

- [Introdução](https://docs.openclaw.ai/start/getting-started)
- [Wizard](https://docs.openclaw.ai/start/wizard)
- [Pairing](https://docs.openclaw.ai/start/pairing)
- [Segurança](https://docs.openclaw.ai/gateway/security)

## Solução de problemas

**"openclaw: command not found"**
```bash
export PATH="$(npm prefix -g)/bin:$PATH"
```

**Canais não conectam**
- Use uma versão compatível do Node.js: 24.22.1+ ou 26.12.1+ (Bun tem problemas de compatibilidade com WhatsApp/Telegram)

**Atualizando uma instância existente**
A versão do Node.js é atualizada automaticamente apenas em imagens recém-criadas. Em uma instância existente, atualize o Node.js antes do OpenClaw:
```bash
curl -fsSL https://deb.nodesource.com/setup_24.x | bash -
apt-get update
apt-get install -y nodejs
node --version
/opt/update-openclaw.sh
```

**Gateway não inicia**
```bash
openclaw health
openclaw status --all
```

**"pairing required" na Control UI**
```bash
openclaw devices list
openclaw devices approve REQUEST_ID
```

**Erro HTTP 502 no navegador**
O Caddy está no ar, mas o Gateway ainda não responde. Após um reinício o Gateway leva cerca de 30 segundos para aceitar requisições. Aguarde:
```bash
/usr/local/bin/openclaw-wait-ready 300 && echo pronto
systemctl status openclaw --no-pager
```

**Erro HTTP 403 `proxy_attribution_required`**
O Gateway não confia no proxy reverso local. Reaplique as configurações de origem (`gateway.trustedProxies`, `gateway.publicOrigin`, `gateway.controlUi.allowedOrigins`) e reinicie:
```bash
/usr/local/bin/openclaw-set-origin https://SEU_IP_OU_DOMINIO
systemctl restart openclaw
```

## Arquitetura

O Gateway escuta apenas em `127.0.0.1:18789`; o Caddy termina o HTTPS na porta 443 e faz o proxy para ele, sobrescrevendo `X-Forwarded-For`/`X-Real-IP` para que o Gateway identifique o cliente real. A porta 18789 nunca é exposta à internet.

| Arquivo | Função |
|---------|--------|
| `/usr/local/bin/openclaw-setup` | Configuração do primeiro boot (token, config, HTTPS, espera de readiness) |
| `/usr/local/bin/openclaw-start` | Inicializador do Gateway usado por `openclaw.service` |
| `/usr/local/bin/openclaw-set-origin` | Define o proxy confiável e as origens do navegador na config |
| `/usr/local/bin/openclaw-write-caddyfile` | Escreve a config de proxy reverso do Caddy |
| `/usr/local/bin/openclaw-wait-ready` | Bloqueia até o Gateway responder no loopback |
