# Hermes Agent One-Click (Ubuntu 26.04)

Imagem one-click da LetsCloud com o [Hermes Agent](https://hermes-agent.nousresearch.com)
da Nous Research pré-instalado, pronto para configurar o provedor de LLM no
primeiro login.

O instalador oficial é executado durante o build, de modo que a instância sobe
com todas as dependências já resolvidas (runtime Python fixado via `uv`,
Node.js e o checkout do agente).

## O que a imagem inclui

- Hermes Agent instalado a partir do instalador oficial (canal `stable`)
- Dependências de build: `ca-certificates`, `curl`, `git`, `gnupg`,
  `lsb-release`, `sudo`, `software-properties-common`
- Symlink `/usr/local/bin/hermes` para uso em qualquer shell e pelo cloud-init
- MOTD com instruções de primeiros passos
- Assistente `hermes setup --portal` disparado no primeiro login
- Unidade systemd de primeiro boot que valida o launcher

## Estrutura

```text
hermes-26-04/
├── hermes-26-04.pkr.hcl                 Template Packer
├── scripts/
│   ├── 011-hermes.sh                    Instalação do Hermes Agent
│   └── 900-cleanup.sh                   Limpeza antes do snapshot
└── files/
    ├── etc/profile.d/hermes-first-login.sh
    │                                     Dispara o assistente no 1º login
    ├── etc/systemd/system/hermes-firstboot.service
    │                                     Preparação por instância
    ├── etc/update-motd.d/99-startup     Mensagem de boas-vindas
    ├── opt/hermes/first-boot.sh         Trabalho de primeiro boot
    └── opt/hermes/first-login.sh        Assistente de configuração
```

## Particularidades do Ubuntu 26.04 na LetsCloud

A imagem base `ubuntu-26.04-x86_64` **não traz cloud-init**. Durante o build o
Packer registra `cloud-init not found; continuing`. Duas consequências moldaram
o desenho desta imagem:

**1. Não existe hook `per-instance`.** O
`/var/lib/cloud/scripts/per-instance/001_onboot` usado pelas demais imagens
nunca executaria. O trabalho por instância foi movido para a unidade
[hermes-firstboot.service](./files/etc/systemd/system/hermes-firstboot.service),
que roda o [first-boot.sh](./files/opt/hermes/first-boot.sh) uma única vez,
protegida pelo marcador `/var/lib/hermes/first-boot.done`.

**2. O `018-force-ssh.sh` não pode ser usado.** O script compartilhado
acrescenta um bloco `Match User root` com `ForceCommand` ao `sshd_config`, e
todas as outras imagens o removem no `001_onboot`. Sem cloud-init nada o
removeria, e **o root ficaria permanentemente trancado fora do VPS**. Como aqui
não há nada a esperar no primeiro boot — o agente é instalado por inteiro no
build —, o guard foi simplesmente retirado da lista de scripts do
[template](./hermes-26-04.pkr.hcl).

## Configuração automática no primeiro login

O agente não faz nada útil enquanto um provedor de LLM não for configurado, e
essa etapa exige terminal — logo, não pode rodar nem durante o build nem no
cloud-init. Por isso o [hermes-first-login.sh](./files/etc/profile.d/hermes-first-login.sh)
é lido por `/etc/profile` em todo shell de login e executa o
[first-login.sh](./files/opt/hermes/first-login.sh), que chama
`hermes setup --portal` logo após o MOTD.

O assistente só é disparado quando todas estas condições são verdadeiras:

| Condição | Motivo |
| --- | --- |
| Shell interativo com TTY | O assistente é interativo |
| `id -u` = `0` | A instalação vive em `/root` |
| `/var/lib/hermes/first-login.done` não existe | Já foi concluído |
| `HERMES_SKIP_FIRST_LOGIN` vazio | Escape manual |

O marcador `/var/lib/hermes/first-login.done` é criado **apenas** quando o
`hermes setup --portal` termina com sucesso: um `Ctrl+C` ou uma falha deixa o
agente inutilizável, então o assistente é oferecido novamente no próximo login.
O [900-cleanup.sh](./scripts/900-cleanup.sh) e o
[first-boot.sh](./files/opt/hermes/first-boot.sh) removem o marcador para que
ele nunca seja herdado pelo snapshot.

Para pular:

```bash
HERMES_SKIP_FIRST_LOGIN=1 ssh root@IP    # apenas nesta sessão
touch /var/lib/hermes/first-login.done   # definitivamente
```

## Onde o Hermes fica instalado

O instalador oficial **não** é system-wide: ele descompacta em
`$HERMES_HOME/hermes-agent` e publica o launcher em `~/.local/bin`, colocando
esse diretório no `PATH` apenas via `~/.bashrc` e `~/.profile`.

Como nem o shell não-interativo do Packer nem o cloud-init leem esses arquivos,
o [011-hermes.sh](./scripts/011-hermes.sh) resolve o launcher pelo caminho
absoluto e cria o symlink:

| Caminho | Conteúdo |
| --- | --- |
| `/root/.hermes/hermes-agent` | Checkout e runtime do agente |
| `/root/.hermes/config.yaml` | Configuração do agente |
| `/usr/local/bin/hermes` | Symlink usado por shells e cloud-init |
| `/opt/hermes/README` | Notas de instalação na própria instância |

Como a instalação vive em `/root`, **o Hermes deve ser executado como root**.
Para liberar outro usuário, reinstale sob o `HOME` dele.

## Como construir

```bash
./build.sh hermes-26-04                  # build completo
./build.sh hermes-26-04 --validate-only  # apenas valida o template
```

O [build.sh](../build.sh) lê o token da API de `~/.letscloud_token` (permissão
`600`). Nunca coloque o token em arquivos dentro do repositório.

Parâmetros do build:

| Parâmetro | Valor |
| --- | --- |
| `location_slug` | `sao2` |
| `plan_slug` | `1vcpu-2gb-50ssd` |
| `image_slug` | `ubuntu-26.04-x86_64` |
| `snapshot_name` | `hermes-26-04` |

### Integridade do snapshot

O snapshot é tirado do dispositivo de bloco, não do page cache do kernel em
execução. Sem um `sync` explícito, qualquer arquivo escrito no fim do build
pode entrar na imagem com o tamanho certo mas a cauda preenchida de bytes
nulos.

Isso não é hipotético: o primeiro build desta imagem perdeu o final do
`/etc/ssh/sshd_config` exatamente assim, porque os únicos `sync` do
[900-cleanup.sh](./scripts/900-cleanup.sh) estavam dentro do ramo de fallback
do zerofill — e, com o `fstrim` bem-sucedido, nunca eram executados. O script
agora faz `sync` antes do `fstrim` e novamente no final.

## Como usar após o deploy

Conecte via SSH como `root`. O assistente `hermes setup --portal` abre
automaticamente; ao final, inicie o agente:

```bash
hermes                  # inicia o agente
```

Se o assistente foi pulado, execute manualmente:

```bash
hermes setup --portal   # assistente guiado pelo portal
```

Configuração manual:

```bash
hermes model           # provedor de LLM e modelo
hermes tools           # ferramentas habilitadas
hermes gateway setup    # plataformas de mensageria
hermes setup            # assistente completo
```

Diagnóstico:

```bash
hermes doctor
```

As etapas interativas (`setup`, `gateway`) são puladas durante o build porque
exigem terminal — é exatamente por isso que o `hermes setup --portal` é
disparado no primeiro login.

## Requisitos mínimos

O plano usado no build é `1vcpu-2gb-50ssd`. O agente baixa um runtime Python
próprio e dependências Node.js, então 2 GB de RAM é o mínimo recomendado;
suba para `2vcpu-4gb-80ssd` se pretende usar o gateway e modelos locais.

## Links

- [Documentação de instalação](https://hermes-agent.nousresearch.com/docs/getting-started/installation)
- [Site do Hermes Agent](https://hermes-agent.nousresearch.com)
