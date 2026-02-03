# OpenClaw One-Click

One-click image with [OpenClaw](https://openclaw.ai) pre-installed. OpenClaw is an open agent platform that runs on your machine and works from the chat apps you already use—WhatsApp, Telegram, Discord, Slack, Teams. Your assistant. Your machine. Your rules.

## What's Included

- **Ubuntu 24.04**
- **Node.js 22.x**
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
   cat /opt/clawdbot/gateway-token.txt
   ```

3. Access the Control UI. HTTPS is enabled on first boot. Run `cat /opt/clawdbot/control-ui-url.txt` to get the URL with token, or see [Gateway Access](#gateway-access) for all options.

4. Configure API keys and channels (optional):
   ```bash
   openclaw onboard --install-daemon
   ```

## Gateway Access

The Gateway is available immediately after first boot. **HTTPS is enabled automatically** with a self-signed certificate. Browsers require HTTPS or localhost. Three access options:

### Option 1 – HTTPS by IP (automatic on first boot)

HTTPS with self-signed certificate is configured automatically. Get the **tokenized URL** (includes token, no manual paste):

```bash
cat /opt/clawdbot/control-ui-url.txt
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

**Token:** `cat /opt/clawdbot/gateway-token.txt` | **URL with token:** `cat /opt/clawdbot/control-ui-url.txt`

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
- **Token**: `/opt/clawdbot/gateway-token.txt`
- **URL with token**: `/opt/clawdbot/control-ui-url.txt` (use this to access Control UI)

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
- Use Node.js 22+ (Bun has compatibility issues with WhatsApp/Telegram)

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

---

# Português

Imagem one-click com [OpenClaw](https://openclaw.ai) pré-instalado. OpenClaw é uma plataforma de agentes abertos que roda na sua máquina e funciona nos apps de chat que você já usa—WhatsApp, Telegram, Discord, Slack, Teams. Seu assistente. Sua máquina. Suas regras.

## O que está incluído

- **Ubuntu 24.04**
- **Node.js 22.x**
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
   cat /opt/clawdbot/gateway-token.txt
   ```

3. Acesse a Control UI. O HTTPS é ativado no primeiro boot. Execute `cat /opt/clawdbot/control-ui-url.txt` para obter a URL com token, ou veja [Acesso ao Gateway](#acesso-ao-gateway) para todas as opções.

4. Configure chaves de API e canais (opcional):
   ```bash
   openclaw onboard --install-daemon
   ```

## Acesso ao Gateway

O Gateway fica disponível logo após o primeiro boot. **HTTPS é ativado automaticamente** com certificado autoassinado. Navegadores exigem HTTPS ou localhost. Três opções de acesso:

### Opção 1 – HTTPS por IP (automático no primeiro boot)

HTTPS com certificado autoassinado é configurado automaticamente. Obtenha a **URL com token** (inclui o token, sem colar manualmente):

```bash
cat /opt/clawdbot/control-ui-url.txt
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

**Token:** `cat /opt/clawdbot/gateway-token.txt` | **URL com token:** `cat /opt/clawdbot/control-ui-url.txt`

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
- **Token**: `/opt/clawdbot/gateway-token.txt`
- **URL com token**: `/opt/clawdbot/control-ui-url.txt` (use para acessar a Control UI)

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
- Use Node.js 22+ (Bun tem problemas de compatibilidade com WhatsApp/Telegram)

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
