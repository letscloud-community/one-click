# RuneScape: Dragonwilds One-Click (Ubuntu 24.04)

Imagem One-Click para hospedar um **servidor dedicado de RuneScape: Dragonwilds**
usando o **container oficial mantido pela Jagex**
([`ghcr.io/runescape/rsdw-dedicated`](https://github.com/runescape/rsdw-dedicated),
licença BSD-3-Clause).

A imagem é construída com Packer sobre Ubuntu 24.04 LTS e segue o modelo faseado
do repositório: prepara tudo durante o build e finaliza a configuração no
primeiro boot, quando o Owner ID do cliente finalmente é conhecido.

## Por que container oficial e não SteamCMD direto

O [guia oficial de dedicated servers](https://dragonwilds.runescape.com/news/how-to-dedicated-servers)
documenta a instalação via SteamCMD (`app_update 4019830`). Em paralelo, a Jagex
publica um container oficial que faz exatamente isso por dentro: a imagem roda
`steamcmd +app_update 4019830` a cada start e gera o `DedicatedServer.ini` a
partir de variáveis de ambiente.

Usar o container oficial entrega o mesmo binário do guia, com atualização
automática no start, isolamento de processo e execução sem privilégios. Nenhuma
imagem de terceiros é utilizada.

## O que a imagem inclui

- Docker Engine (repositório oficial) com limites de log e `live-restore`
- Container oficial da Jagex pré-baixado (cerca de 500 MB)
- Estrutura completa em `/opt/dragonwilds`
- Wizard de primeiro boot que coleta o Owner ID e sobe o servidor
- Firewall UFW com política `deny incoming` e apenas SSH mais as duas portas
  UDP do jogo abertas
- Backup automático horário com retenção em três níveis
- Restore guiado com backup de segurança automático
- Atualização controlada por janela de manutenção, sem derrubar sessão ativa
- Serviço systemd com start automático no reboot
- Rotação de logs via logrotate
- MOTD que muda de acordo com o estado da instalação

## Estrutura

```
dragonwilds-24-04/
├── dragonwilds-24-04.pkr.hcl             # Configuração do build Packer
├── README.md                             # Este arquivo
├── scripts/
│   └── 011-dragonwilds.sh                # Preparação em tempo de build
└── files/
    ├── etc/
    │   ├── logrotate.d/dragonwilds       # Rotação dos logs
    │   ├── systemd/system/
    │   │   ├── dragonwilds.service       # Start automático no boot
    │   │   ├── dragonwilds-backup.service
    │   │   ├── dragonwilds-backup.timer  # Backup horário
    │   │   ├── dragonwilds-update.service
    │   │   └── dragonwilds-update.timer  # Verificação de atualização
    │   └── update-motd.d/99-startup      # Message of the Day
    ├── opt/dragonwilds/
    │   ├── docker-compose.yml            # Definição do serviço
    │   ├── env.example                   # Template de configuração
    │   └── scripts/
    │       ├── common.sh                 # Funções compartilhadas
    │       ├── first-boot.sh             # Wizard de configuração inicial
    │       ├── start.sh / stop.sh / restart.sh
    │       ├── status.sh / logs.sh
    │       ├── backup.sh                 # Backup com retenção
    │       ├── restore.sh                # Restauração guiada
    │       └── update.sh                 # Atualização controlada
    └── var/lib/cloud/scripts/per-instance/
        └── 001_onboot                    # Inicialização no primeiro boot
```

Em runtime, o diretório fica assim:

```
/opt/dragonwilds/
├── docker-compose.yml
├── env.example
├── .env                   # Gerado no 1o boot, root:root, modo 600
├── data/                  # Volume persistente (uid 1000)
│   └── RSDragonwilds/Saved/
│       ├── SaveGames/     # Os mundos (.sav)
│       ├── Config/LinuxServer/DedicatedServer.ini
│       └── Logs/RSDragonwilds.log
├── backups/
│   ├── hourly/ daily/ weekly/
│   └── manual/ pre-update/ pre-restore/
└── scripts/
```

## Fases da instalação

**1. Build (`scripts/011-dragonwilds.sh`)**, prepara mas não inicia:
- Atualiza o sistema e instala dependências (curl, jq, ufw, conntrack, logrotate)
- Instala o Docker Engine oficial e configura `daemon.json`
- Cria `/opt/dragonwilds/{data,backups,scripts}` com as permissões corretas
- Faz pull do container oficial da Jagex
- Pré-configura o UFW sem ativá-lo, para não derrubar a sessão SSH do Packer
- Habilita os units systemd, que ficam inertes enquanto não existir `.env`

**2. Primeiro boot (`001_onboot`)**:
- Remove o `ForceCommand` de SSH e ativa o UFW
- Recria a árvore de diretórios e reaplica o ownership `1000:1000`
- Procura um Owner ID fornecido no provisionamento (arquivo ou cloud-init)
- Se encontrar, roda o setup sozinho. Se não, arma o wizard para o primeiro login
- Ativa os timers de backup e atualização
- Remove a si mesmo

**3. Configuração (`first-boot.sh`)**:
- Valida o Owner ID e os demais parâmetros
- Gera o `.env` com senhas aleatórias de 20 caracteres
- Libera as portas do jogo (`7777/udp`) e do beacon (`8888/udp`) no firewall
- Sobe o servidor e confirma que o container não morreu logo em seguida
- Grava o resumo em `/root/dragonwilds_info.txt` e cria o marcador que impede
  uma segunda execução

## Como construir

Guarde o token da API uma única vez, com permissão restrita:

```bash
install -m 600 /dev/null ~/.letscloud_token
read -rsp 'Token: ' T && printf '%s' "$T" > ~/.letscloud_token && unset T
```

Depois, a partir da raiz do repositório:

```bash
./build.sh dragonwilds-24-04                  # build completo
./build.sh dragonwilds-24-04 --validate-only  # só valida o template
```

O `build.sh` passa o token via `PKR_VAR_api_key`, de modo que ele não aparece
na lista de processos, e grava a saída completa em `packer-build.log`.

### Ordem dos provisioners e por que ela importa

A imagem base do Ubuntu 24.04 da LetsCloud chega centenas de pacotes atrás.
Atualizar `openssh-server`, `systemd` e o kernel por SSH derruba a sessão do
Packer no meio de uma transação do `dpkg`, o que deixaria pacotes pela metade.
O build resolve isso desacoplando o upgrade da sessão:

1. **Preparação:** desabilita `needrestart` e `unattended-upgrades`, que
   reiniciam o `sshd` durante a instalação de pacotes.
2. **`scripts/005-system-upgrade.sh`:** dispara o `full-upgrade` como unidade
   transiente do systemd (`systemd-run --no-block`), fora da sessão SSH. O
   progresso é sinalizado por `/var/lib/packer-upgrade.done`, que guarda o
   código de saída. Há até 4 tentativas, porque o `archive.ubuntu.com` é um
   round robin e espelhos individuais recusam conexão de vez em quando.
3. **Espera:** tolera quantas desconexões forem necessárias. Ao terminar, o
   worker reinicia a máquina, criando um ponto único e previsível de reconexão.
4. **Pós-reboot:** confirma que restam **zero** pacotes pendentes e falha o
   build caso contrário, em vez de gerar um snapshot pela metade.
5. **Upload de `files/`:** só aqui, nunca antes do reboot, para que o
   cloud-init não execute o `001_onboot` durante o build.
6. **`011-dragonwilds.sh`**, `018-force-ssh.sh` e `900-cleanup.sh`.

O `900-cleanup.sh` é uma versão local, e não o de `common-scripts/`: o
compartilhado termina com um `dd if=/dev/zero` sem limite, que enche o disco a
100%. Com o disco cheio o `sshd` para de escrever e o build cai. Aqui usa-se
`fstrim`, que libera o espaço instantaneamente.

## Como usar após o deploy

### Caminho interativo

1. Crie a instância a partir do snapshot.
2. Conecte via SSH. O wizard abre sozinho no primeiro login.
3. Informe o Owner ID quando solicitado.

O wizard é disparado por `/etc/profile.d/dragonwilds-first-boot.sh`, que já vem
dentro da imagem e é lido por todo shell de login. Ele foi colocado ali de
propósito: antes a chamada era acrescentada ao `/root/.bashrc` durante o
primeiro boot, o que fazia o prompt depender daquela etapa ter terminado bem.
Bastava uma falha ali para o cliente entrar e não receber pergunta nenhuma.

Para entrar sem ser interrompido pelo wizard, use `DW_SKIP_FIRST_BOOT=1`.

### Caminho automatizado (one-click de verdade)

Para que o cliente não precise nem abrir o SSH, entregue o Owner ID no
provisionamento, de uma destas duas formas:

```bash
# cloud-init user-data
#cloud-config
write_files:
  - path: /etc/dragonwilds/owner-id
    content: "0123456789abcdef0123456789abcdef"
```

ou simplesmente uma linha contendo `DW_OWNER_ID=<id>` no user-data. O
`001_onboot` detecta o valor e executa a configuração sem nenhuma interação.

Também é possível rodar manualmente a qualquer momento:

```bash
/opt/dragonwilds/scripts/first-boot.sh --owner-id <SEU_ID> --non-interactive
```

### Onde encontrar o Owner ID

No jogo, em **Settings**, role até o final do menu. Há um botão de cópia ao lado
do Player ID. **O servidor não inicia sem esse valor.**

### Como os jogadores entram

Pelo **join code** publicado a cada start (`status.sh` mostra o atual), que
dispensa qualquer busca, ou na tela **Worlds**, aba **Public**, pesquisando o
**nome do mundo exatamente como configurado** — a busca diferencia maiúsculas
de minúsculas e respeita o limite de 16 caracteres descrito acima.

O primeiro start baixa cerca de 5,5 GB via SteamCMD, então o mundo leva alguns
minutos para aparecer. Acompanhe com `/opt/dragonwilds/scripts/logs.sh` e
aguarde `START SESSION - Success`.

## Scripts de gerenciamento

| Script | Descrição |
|--------|-----------|
| `/opt/dragonwilds/scripts/status.sh` | Status, dados de conexão, mundos, backups e timers |
| `/opt/dragonwilds/scripts/logs.sh` | Logs do container. Use `--game` para o log do jogo |
| `/opt/dragonwilds/scripts/start.sh` | Inicia o servidor |
| `/opt/dragonwilds/scripts/stop.sh` | Para o servidor aguardando o save final |
| `/opt/dragonwilds/scripts/restart.sh` | Reinicia aplicando alterações do `.env` |
| `/opt/dragonwilds/scripts/backup.sh` | Backup imediato dos mundos |
| `/opt/dragonwilds/scripts/restore.sh` | Restaura um mundo a partir de um backup |
| `/opt/dragonwilds/scripts/update.sh` | Verifica e aplica atualizações do jogo |
| `/opt/dragonwilds/scripts/firewall.sh` | Reaplica as regras. Use `--status` para inspecionar |
| `/opt/dragonwilds/scripts/first-boot.sh` | Reconfiguração completa, com `--force` |

## Configuração

Todo o comportamento do servidor vem de `/opt/dragonwilds/.env`. O container
regenera o `DedicatedServer.ini` a partir dessas variáveis a cada start, então
**editar o `.ini` dentro de `data/` não tem efeito duradouro**, conforme aviso
da própria documentação oficial.

Depois de alterar o `.env`:

```bash
/opt/dragonwilds/scripts/restart.sh
```

Principais variáveis:

| Variável | Padrão | Descrição |
|----------|--------|-----------|
| `RSDW_OWNER_ID` | (vazio) | EOS Online ID do dono. Obrigatório |
| `RSDW_WORLD_NAME` | gerado | Nome pesquisado no browser. **Máx. 16 caracteres** |
| `RSDW_SERVER_NAME` | `letscloud-dw` | Nome na coluna "Created By". **Máx. 16 caracteres** |
| `RSDW_PORT` | `7777` | Porta UDP do jogo. Fixa, não deve ser alterada |
| `RSDW_BEACON_PORT` | `8888` | Porta UDP do beacon. Obrigatória, não deve ser alterada |
| `RSDW_PASSWORD` | gerada | Senha do mundo. Vazio deixa aberto |
| `RSDW_ADMIN_PASSWORD` | gerada | Acesso à tela de Server Management |
| `RSDW_ADMINS` | (vazio) | Lista de EOS IDs com permissão de admin |
| `DW_UPDATE_MODE` | `window` | `notify`, `window` ou `immediate` |
| `DW_UPDATE_WINDOW_HOUR` | `5` | Hora da janela de manutenção |
| `DW_KEEP_HOURLY/DAILY/WEEKLY` | `24/7/4` | Retenção dos backups |

> **Atenção:** nunca defina uma senha com o valor literal `random`. O container
> oficial interpreta essa palavra como "gerar uma nova a cada start", o que
> trocaria a senha a cada reinício. O `first-boot.sh` bloqueia esse valor.

### Limite de 16 caracteres nos nomes

O jogo publica o nome do mundo e o do servidor no browser como atributos de
sessão do EOS **limitados a 16 caracteres**, e corta silenciosamente o que
passar disso. Verificado no log do servidor:

```
LogNetSessionSettings: SlotName truncated to fit max length
  was[ABCDEFGHIJKLMNOPQRSTUVWXYZ] now[ABCDEFGHIJKLMNOP]
```

O save local preserva o nome inteiro, então o sintoma é traiçoeiro: o servidor
sobe normalmente, mas quem recebeu o nome completo pesquisa por algo que o
browser nunca devolve. O wizard rejeita nomes mais longos no modo interativo e
os trunca com aviso no modo automático, de forma que o `.env`, o resumo e o
browser mostrem sempre a mesma string.

### Join code

A cada start o servidor publica um **join code** (formato `XXXX-XXXX`), que
dispensa a busca por nome. Ele muda sempre que o container é recriado, e por
isso é lido do log ao vivo:

```bash
/opt/dragonwilds/scripts/status.sh    # mostra o join code atual
```

Ele também aparece no MOTD e no `/root/dragonwilds_info.txt`.

## Portas do firewall

| Porta | Protocolo | Serviço |
|-------|-----------|---------|
| 22 | TCP | SSH |
| 7777 | UDP | RuneScape: Dragonwilds (game port) |
| 8888 | UDP | RuneScape: Dragonwilds (beacon port) |

A política padrão é `deny incoming` e `allow outgoing`. Nenhuma outra porta é
aberta.

Todas as alterações passam por `scripts/firewall.sh`, que nunca ativa o UFW sem
antes **confirmar que a porta do SSH está liberada**. Se a regra estiver
ausente, ele aborta com erro em vez de ativar um firewall `deny incoming` que
deixaria a instância inacessível. Quando o UFW já está ativo, ele usa `reload`
em vez de desligar e religar, para não derrubar a sessão em uso. O script também
detecta a porta real do `sshd` em `sshd_config`, caso ela tenha sido alterada.

Para inspecionar ou reaplicar:

```bash
/opt/dragonwilds/scripts/firewall.sh --status
/opt/dragonwilds/scripts/firewall.sh
```

Vale notar que containers com portas publicadas são liberados pelo Docker
diretamente no iptables, contornando o UFW. A regra explícita de UDP é mantida
assim mesmo, para que a intenção fique visível no `ufw status`.

O jogo usa **UDP**, e a porta **7777 é fixa nesta imagem**. A documentação
oficial indica que apenas um segundo servidor no mesmo host passaria a usar
7778 em diante, cenário fora do escopo aqui, já que a imagem roda um servidor
por VPS. Manter o valor fixo garante que a regra do UFW, o `docker-compose.yml`
e o endereço informado aos jogadores nunca saiam de sincronia.

Além da porta do jogo, o servidor precisa da **porta de beacon (`8888/udp`,
convenção de porta do jogo + 1111)**. É por ela que o browser de mundos anuncia
e alcança o servidor. O [README do container oficial](https://github.com/runescape/rsdw-dedicated)
é explícito: se `RSDW_PORT` e `RSDW_BEACON_PORT` não estiverem acessíveis, o
mundo até aparece na lista e a entrada falha com *"connection lost"*. Por isso
as duas portas são publicadas no compose e liberadas no UFW.

## Requisitos

A documentação oficial define a memória por jogador, e o repositório do
container define o mínimo absoluto:

| Jogadores | RAM | Observação |
|-----------|-----|------------|
| 2 | 4 GB | Fórmula oficial: 2 GB + 1 GB por jogador |
| 4 | 6 GB | |
| 6 | 8 GB | Máximo suportado pelo jogo na versão 0.11 |

- CPU: 1 core no mínimo, 2 recomendados
- Disco: a instalação ocupa cerca de 5,5 GB; reserve 20 GB para cobrir backups
  e o crescimento das builds futuras
- Sistema operacional 64 bits, obrigatoriamente

Planos da LetsCloud correspondentes:

| Plano | Jogadores | Observação |
|-------|-----------|------------|
| `2vcpu-4gb-80ssd` | até 2 | Padrão do template |
| `4vcpu-8gb-160ssd` | até 6 | Máximo suportado pelo jogo |

Planos com 1 ou 2 GB de RAM não atendem, porque a fórmula oficial reserva 2 GB
para o servidor antes do primeiro jogador.

## Estratégia de atualização

Esta é a parte mais delicada da operação, porque **cliente e servidor precisam
rodar a mesma versão**. Um servidor desatualizado simplesmente desaparece do
browser de mundos.

**Como o container se comporta.** A imagem oficial roda `app_update` a cada
start, ou seja, reiniciar o container **é** atualizar. Enquanto roda, ela
consulta a API UpToDateCheck da Valve a cada 30 minutos e, se
`RSDW_AUTO_STOP_ON_UPDATE=true`, encerra o processo assim que uma build nova
aparece, contando com a política de restart para voltar atualizada.

**Por que esse modo automático fica desligado.** Ele derruba os jogadores no
exato instante em que a Jagex publica uma build, no meio da sessão. É o cenário
que o pedido original pede para evitar.

**O que a imagem faz no lugar.** O `dragonwilds-update.timer` roda de hora em
hora e o `update.sh` aplica esta sequência de travas:

1. Consulta a API da Valve com o build id instalado.
2. Só age dentro da janela de manutenção (`DW_UPDATE_WINDOW_HOUR`, padrão 5h).
3. Só age se não houver nenhuma conexão ativa na porta UDP do jogo.
4. Faz um **backup a frio** antes de encostar em qualquer coisa.
5. Recria o container, o que dispara o `app_update`.
6. Confirma que o servidor voltou e registra tudo em `/var/log/dragonwilds/`.

O mundo fica em um bind mount que nunca é apagado, então a atualização troca
apenas os binários do jogo.

**Uma ressalva importante e verificada.** No momento da escrita, a API
UpToDateCheck responde `Couldn't get app info for the app specified` para o
appid 4019830. O container oficial esbarra no mesmo limite e apenas segue
rodando, o que na prática significaria nunca atualizar. Por isso o `update.sh`
tem um fallback: quando a API não sabe responder, ele faz um restart de
manutenção periódico (padrão: no máximo uma vez por dia, ainda respeitando
janela e ausência de jogadores) e deixa o SteamCMD decidir. Se já estiver na
versão corrente, o `app_update` não faz nada.

Modos disponíveis em `DW_UPDATE_MODE`:

- `notify`: apenas registra no log, nada é reiniciado. Controle totalmente manual
- `window`: padrão, atualiza na janela de manutenção e somente se estiver ocioso
- `immediate`: atualiza assim que estiver ocioso, em qualquer horário

Para aplicar na hora, ignorando janela e verificação de jogadores:

```bash
/opt/dragonwilds/scripts/update.sh --check   # só verifica
/opt/dragonwilds/scripts/update.sh --now     # aplica imediatamente
```

## Backups

O `dragonwilds-backup.timer` roda a cada hora, aos 7 minutos. A retenção padrão
segue a sugestão do pedido:

| Nível | Quantidade | Quando |
|-------|-----------|--------|
| Horário | 24 | Toda hora |
| Diário | 7 | Às 4h |
| Semanal | 4 | Domingo às 4h |

Um backup diário é um **hardlink** do horário correspondente, então promover uma
cópia não duplica espaço em disco.

**O que entra no arquivo:** os `.sav` dos mundos e o `DedicatedServer.ini`, que
carrega o `ServerGuid`. Os cerca de 5,5 GB de instalação do jogo ficam de fora
de propósito, porque o SteamCMD sempre consegue baixá-los de novo e incluí-los
tornaria o backup horário inviável.

### É preciso parar o servidor para o backup ser consistente?

Resposta curta: **não para o backup rotineiro, sim para o que precede uma
operação destrutiva.**

O servidor dedicado não expõe nenhum comando de "flush para disco sob demanda",
e a documentação oficial trata backup como "copie os arquivos de `SaveGames`".
Como o jogo grava o mundo em autosaves periódicos, e não continuamente, existe
uma janela ampla entre escritas. O backup padrão é **a quente** e aproveita
isso com três cuidados:

1. Antes de arquivar, amostra tamanho e mtime de todos os `.sav` duas vezes com
   3 segundos de intervalo, e só prossegue quando nada mudou, o que indica que
   nenhum autosave está em andamento.
2. Grava em um arquivo `.partial` e só renomeia no final, para nunca existir um
   arquivo pela metade com nome de backup válido.
3. Valida o resultado com `tar -tzf` e confere que há pelo menos um `.sav`
   dentro. Se a validação falhar, o arquivo é descartado em vez de virar um
   backup inútil. Um `.sha256` acompanha cada arquivo.

Quando a garantia precisa ser absoluta, o backup é **a frio**: o container é
parado, o que força o save final, a cópia é feita e o servidor volta. É o que
acontece automaticamente antes de toda atualização e de todo restore. Para
forçar manualmente:

```bash
/opt/dragonwilds/scripts/backup.sh --cold
```

Para tornar o backup a frio o padrão de todas as execuções agendadas, basta
definir `DW_BACKUP_COLD=true` no `.env`. Isso troca consistência garantida por
uma pequena indisponibilidade a cada hora.

### Backup manual

```bash
/opt/dragonwilds/scripts/backup.sh
/opt/dragonwilds/scripts/backup.sh --label antes-de-testar-mod
```

Os backups ficam em `/opt/dragonwilds/backups/`, no disco da própria instância.

## Restore

```bash
/opt/dragonwilds/scripts/restore.sh            # lista e pergunta
/opt/dragonwilds/scripts/restore.sh --list     # apenas lista
/opt/dragonwilds/scripts/restore.sh --latest --yes
```

O processo é sempre este:

1. Lista os backups disponíveis com tamanho e data.
2. Recebe a escolha, ou aceita `--file` / `--latest`.
3. Confere o `.sha256` e testa a integridade do arquivo **antes** de parar o
   servidor. Um arquivo corrompido aborta sem causar dano.
4. Para o servidor, aguardando o save final.
5. Cria um backup de segurança do estado atual em `backups/pre-restore/`. Se
   esse backup falhar, o restore é abortado e o servidor volta ao ar intacto.
6. Extrai para um diretório temporário e só então substitui os mundos, para que
   uma falha no meio do caminho não deixe o `SaveGames` misturado.
7. Reaplica o ownership `1000:1000`.
8. Sobe o servidor e confirma que subiu.

O servidor é obrigatoriamente parado porque ele carrega o mundo na memória no
start e o regrava no autosave seguinte. Trocar os arquivos com o servidor no ar
faria o mundo restaurado ser sobrescrito.

## Segurança

- **Container sem privilégios**: `no-new-privileges`, `cap_drop: ALL` e execução
  como uid 1000, sem `privileged` e sem acesso ao socket do Docker
- **Exposição mínima**: apenas 22/tcp, 7777/udp e 8888/udp, com `deny incoming`
  como padrão
- **Proteção do `.env`**: criado direto em modo `0600` e `root:root`, então as
  senhas nunca existem com permissão frouxa nem por um instante
- **Nenhuma senha hardcoded**: tudo é gerado por instância com `openssl rand`,
  em 20 caracteres sem glifos ambíguos
- **Parsing seguro do `.env`**: o arquivo é interpretado linha a linha em vez de
  usar `source`, porque os valores são gravados sem aspas para o docker compose.
  Uma senha contendo espaço, `|` ou `&` seria executada como código pelo `.`
- **Proteção contra reexecução**: o `001_onboot` é removido pelo cloud-init e
  por si mesmo, e o `first-boot.sh` verifica um marcador antes de rodar
- **Logs rotacionados**: logrotate para os scripts e para o log do jogo, mais
  limite de tamanho no json-file driver do Docker
- **Desligamento seguro**: `stop_grace_period` de 120 segundos, para o mundo
  nunca ser truncado por um SIGKILL prematuro

## Limitações conhecidas

Levantadas na documentação oficial e no repositório do container:

- Máximo de **6 jogadores** simultâneos na versão 0.11 (março de 2026)
- Convites via Steam não conectam corretamente em servidores dedicados
- Alterar o `DedicatedServer.ini` com o servidor no ar não tem efeito
- O servidor carrega o `.sav` mais recente de `SaveGames` ao iniciar. Se a pasta
  estiver vazia, ele cria um mundo padrão
- Só o Owner pode banir e desbanir offline. Admins banem apenas quem está online

## Links

- Guia oficial: https://dragonwilds.runescape.com/news/how-to-dedicated-servers
- Container oficial: https://github.com/runescape/rsdw-dedicated
- Wiki: https://dragonwilds.runescape.wiki/w/Dedicated_Servers
