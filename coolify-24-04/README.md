# Coolify One-Click (Ubuntu 24.04)

Imagem One-Click do [Coolify](https://coolify.io), a plataforma open-source
self-hosted para deploy de aplicações, bancos de dados e serviços (alternativa a
Heroku, Netlify e Vercel).

A imagem é construída com Packer sobre Ubuntu 24.04 LTS e segue o modelo faseado:
prepara tudo durante o build e finaliza a instalação no primeiro boot, gerando
segredos únicos por instância.

## O que a imagem inclui

- Docker Engine (instalação oficial) com limites de log configurados
- Estrutura completa do Coolify em `/data/coolify`
- Arquivos de configuração baixados do CDN oficial da Coolify
- Firewall UFW pré-configurado (22, 80, 443, 8000, 6001, 6002)
- Serviço systemd `coolify.service` (auto-start no boot)
- Scripts de gerenciamento em `/opt`
- Wizard interativo de ativação de localhost no primeiro login SSH
- MOTD com instruções de acesso

## Estrutura

```
coolify-24-04/
├── coolify-24-04.pkr.hcl                 # Configuração do build Packer
├── README.md                             # Este arquivo
├── scripts/
│   └── 011-coolify.sh                    # Preparação em tempo de build
└── files/
    ├── etc/
    │   ├── systemd/system/
    │   │   └── coolify.service           # Unit systemd
    │   └── update-motd.d/
    │       └── 99-startup                # Message of the Day
    ├── opt/
    │   ├── start-coolify.sh              # Inicia os containers
    │   ├── stop-coolify.sh               # Para os containers
    │   ├── restart-coolify.sh            # Reinicia os containers
    │   ├── update-coolify.sh             # Atualiza para a última versão
    │   ├── coolify-logs.sh               # Logs em tempo real
    │   ├── coolify-status.sh             # Status dos containers
    │   ├── coolify_localhost_setup.sh    # Wizard interativo (1º login)
    │   └── configure-coolify-localhost.sh # Ativação não-interativa de localhost
    └── var/
        └── lib/cloud/scripts/per-instance/
            └── 001_onboot                # Inicialização no primeiro boot
```

## Fases da instalação

**1. Build (`scripts/011-coolify.sh`)** — prepara, mas não inicia:
- Atualiza o sistema e instala dependências (curl, git, jq, openssl, ufw, etc.)
- Instala o Docker Engine oficial e configura `daemon.json`
- Cria `/data/coolify/{source,ssh,applications,databases,backups,services,proxy,...}`
- Baixa `docker-compose.yml`, `docker-compose.prod.yml`, `.env.production` e `upgrade.sh` do CDN
- Pré-configura o UFW, cria a rede Docker `coolify` e habilita o serviço systemd

**2. Primeiro boot (`001_onboot`)** — finaliza e sobe:
- Remove o `ForceCommand` de SSH e ativa o UFW
- Gera uma chave SSH ed25519 única (sem adicionar ao `authorized_keys`)
- **Rotaciona segredos por instância** (`APP_ID`, `APP_KEY`, `DB_PASSWORD`,
  `REDIS_PASSWORD`, `PUSHER_*`) via `openssl`
- Sobe os containers com `docker compose up -d`
- Grava `/root/coolify_info.txt` e registra o wizard de localhost no `.bashrc`

**3. Primeiro login SSH (`coolify_localhost_setup.sh`)**:
- Pergunta se deseja ativar o servidor localhost para deploys
- Se sim, adiciona a chave ao `authorized_keys` e reinicia o Coolify
- Executa apenas uma vez

## Como construir

```bash
packer init coolify-24-04.pkr.hcl
packer validate -var "api_key=SEU_TOKEN" coolify-24-04.pkr.hcl
packer build   -var "api_key=SEU_TOKEN" coolify-24-04.pkr.hcl
```

## Como usar após o deploy

1. Crie uma instância a partir do snapshot (mínimo 2 vCPU / 2 GB RAM / 30 GB).
2. Aguarde de 3 a 5 minutos para o primeiro boot concluir.
3. Acesse `http://SEU_IP:8000` e **crie o admin imediatamente**.
4. (Opcional) Ative o localhost via SSH: o wizard aparece no primeiro login, ou
   rode `/opt/configure-coolify-localhost.sh`.

## Portas do firewall

| Porta | Serviço | Descrição |
|-------|---------|-----------|
| 22 | SSH | Acesso remoto |
| 80 | HTTP | Tráfego web / Let's Encrypt |
| 443 | HTTPS | Tráfego web seguro |
| 8000 | Coolify UI | Interface web |
| 6001 | Realtime | Atualizações em tempo real |
| 6002 | Soketi | Servidor WebSocket |

## Requisitos mínimos

- CPU: 2 cores
- RAM: 2 GB
- Disco: 30 GB

Para produção com múltiplas aplicações, recomenda-se 4+ cores, 8+ GB de RAM e
100+ GB de disco.

## Atualização

```bash
/opt/update-coolify.sh
```

## Links

- Documentação: https://coolify.io/docs
- GitHub: https://github.com/coollabsio/coolify
- Comunidade: https://coolify.io/discord
