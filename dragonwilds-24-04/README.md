# RuneScape: Dragonwilds One-Click (Ubuntu 24.04)

One-Click image for hosting a **RuneScape: Dragonwilds dedicated server** using
the **official container maintained by Jagex**
([`ghcr.io/runescape/rsdw-dedicated`](https://github.com/runescape/rsdw-dedicated),
BSD-3-Clause license).

The image is built with Packer on top of Ubuntu 24.04 LTS and follows the
repository's phased model: everything is prepared during the build, and the
configuration is finished on first boot, when the customer's Owner ID is finally
known.

## Why the official container instead of SteamCMD directly

The [official dedicated servers guide](https://dragonwilds.runescape.com/news/how-to-dedicated-servers)
documents installation through SteamCMD (`app_update 4019830`). In parallel,
Jagex publishes an official container that does exactly that internally: the
image runs `steamcmd +app_update 4019830` on every start and generates
`DedicatedServer.ini` from environment variables.

Using the official container delivers the same binary as the guide, with
automatic updates on start, process isolation and unprivileged execution. No
third-party image is used.

## What the image includes

- Docker Engine (official repository) with log limits and `live-restore`
- The official Jagex container pre-pulled (about 500 MB)
- Full directory structure under `/opt/dragonwilds`
- A first-boot wizard that collects the Owner ID and starts the server
- UFW firewall with a `deny incoming` policy and only SSH plus the two game UDP
  ports open
- Automatic hourly backups with three-tier retention
- Guided restore with an automatic safety backup
- Updates controlled by a maintenance window, without dropping an active session
- systemd service with automatic start on reboot
- Log rotation through logrotate
- MOTD that changes according to the installation state

## Structure

```
dragonwilds-24-04/
├── dragonwilds-24-04.pkr.hcl             # Packer build configuration
├── README.md                             # This file
├── scripts/
│   └── 011-dragonwilds.sh                # Build-time preparation
└── files/
    ├── etc/
    │   ├── logrotate.d/dragonwilds       # Log rotation
    │   ├── systemd/system/
    │   │   ├── dragonwilds.service       # Automatic start on boot
    │   │   ├── dragonwilds-backup.service
    │   │   ├── dragonwilds-backup.timer  # Hourly backup
    │   │   ├── dragonwilds-update.service
    │   │   └── dragonwilds-update.timer  # Update check
    │   └── update-motd.d/99-startup      # Message of the Day
    ├── opt/dragonwilds/
    │   ├── docker-compose.yml            # Service definition
    │   ├── env.example                   # Configuration template
    │   └── scripts/
    │       ├── common.sh                 # Shared functions
    │       ├── first-boot.sh             # Initial configuration wizard
    │       ├── start.sh / stop.sh / restart.sh
    │       ├── status.sh / logs.sh
    │       ├── backup.sh                 # Backup with retention
    │       ├── restore.sh                # Guided restore
    │       └── update.sh                 # Controlled update
    └── var/lib/cloud/scripts/per-instance/
        └── 001_onboot                    # First-boot initialization
```

At runtime, the directory looks like this:

```
/opt/dragonwilds/
├── docker-compose.yml
├── env.example
├── .env                   # Generated on 1st boot, root:root, mode 600
├── data/                  # Persistent volume (uid 1000)
│   └── RSDragonwilds/Saved/
│       ├── SaveGames/     # The worlds (.sav)
│       ├── Config/LinuxServer/DedicatedServer.ini
│       └── Logs/RSDragonwilds.log
├── backups/
│   ├── hourly/ daily/ weekly/
│   └── manual/ pre-update/ pre-restore/
└── scripts/
```

## Installation phases

**1. Build (`scripts/011-dragonwilds.sh`)**, prepares but does not start:
- Updates the system and installs dependencies (curl, jq, ufw, conntrack, logrotate)
- Installs the official Docker Engine and configures `daemon.json`
- Creates `/opt/dragonwilds/{data,backups,scripts}` with the correct permissions
- Pulls the official Jagex container
- Pre-configures UFW without enabling it, so Packer's SSH session is not dropped
- Enables the systemd units, which stay inert while no `.env` exists

**2. First boot (`001_onboot`)**:
- Removes the SSH `ForceCommand` and enables UFW
- Recreates the directory tree and reapplies `1000:1000` ownership
- Looks for an Owner ID supplied at provisioning time (file or cloud-init)
- If found, runs the setup unattended. If not, arms the wizard for the first login
- Enables the backup and update timers
- Removes itself

**3. Configuration (`first-boot.sh`)**:
- Validates the Owner ID and the remaining parameters
- Generates `.env` with random 20-character passwords
- Opens the game (`7777/udp`) and beacon (`8888/udp`) ports in the firewall
- Starts the server and confirms the container did not die right afterwards
- Writes the summary to `/root/dragonwilds_info.txt` and creates the marker that
  prevents a second run

## How to build

Store the API token once, with restricted permissions:

```bash
install -m 600 /dev/null ~/.letscloud_token
read -rsp 'Token: ' T && printf '%s' "$T" > ~/.letscloud_token && unset T
```

Then, from the repository root:

```bash
./build.sh dragonwilds-24-04                  # full build
./build.sh dragonwilds-24-04 --validate-only  # validate the template only
```

`build.sh` passes the token through `PKR_VAR_api_key`, so it never shows up in
the process list, and writes the complete output to `packer-build.log`.

### Provisioner order and why it matters

LetsCloud's Ubuntu 24.04 base image arrives hundreds of packages behind.
Upgrading `openssh-server`, `systemd` and the kernel over SSH drops Packer's
session in the middle of a `dpkg` transaction, which would leave packages
half-configured. The build solves this by decoupling the upgrade from the
session:

1. **Preparation:** disables `needrestart` and `unattended-upgrades`, which
   restart `sshd` during package installation.
2. **`scripts/005-system-upgrade.sh`:** launches the `full-upgrade` as a
   transient systemd unit (`systemd-run --no-block`), outside the SSH session.
   Progress is signalled by `/var/lib/packer-upgrade.done`, which stores the
   exit code. There are up to 4 attempts, because `archive.ubuntu.com` is a
   round robin and individual mirrors refuse connections now and then.
3. **Wait:** tolerates as many disconnects as needed. When it finishes, the
   worker reboots the machine, creating a single predictable reconnection point.
4. **Post-reboot:** confirms that **zero** packages remain pending and fails the
   build otherwise, instead of producing a half-finished snapshot.
5. **`files/` upload:** only at this point, never before the reboot, so that
   cloud-init does not run `001_onboot` during the build.
6. **`011-dragonwilds.sh`**, `018-force-ssh.sh` and `900-cleanup.sh`.

`900-cleanup.sh` is a local version, not the one from `common-scripts/`: the
shared one ends with an unbounded `dd if=/dev/zero`, which fills the disk to
100%. With a full disk, `sshd` stops writing and the build fails. This one uses
`fstrim`, which frees the space instantly.

## How to use after deployment

### Interactive path

1. Create the instance from the snapshot.
2. Connect over SSH. The wizard opens by itself on the first login.
3. Enter the Owner ID when prompted.

The wizard is triggered by `/etc/profile.d/dragonwilds-first-boot.sh`, which
ships inside the image and is sourced by every login shell. It was put there on
purpose: previously the call was appended to `/root/.bashrc` during the first
boot, which made the prompt depend on that step having finished cleanly. A single
failure there was enough for the customer to log in and never be asked anything.

To log in without being interrupted by the wizard, use `DW_SKIP_FIRST_BOOT=1`.

### Automated path (true one-click)

So the customer does not even need to open SSH, supply the Owner ID at
provisioning time, in one of these two ways:

```bash
# cloud-init user-data
#cloud-config
write_files:
  - path: /etc/dragonwilds/owner-id
    content: "0123456789abcdef0123456789abcdef"
```

or simply a line containing `DW_OWNER_ID=<id>` in the user-data. `001_onboot`
detects the value and runs the configuration with no interaction at all.

It can also be run manually at any time:

```bash
/opt/dragonwilds/scripts/first-boot.sh --owner-id <YOUR_ID> --non-interactive
```

### Where to find the Owner ID

In the game, under **Settings**, scroll to the bottom of the menu. There is a
copy button next to the Player ID. **The server does not start without this
value.**

### How players join

Through the **join code** published on every start (`status.sh` shows the current
one), which removes the need for any search, or on the **Worlds** screen,
**Public** tab, searching for the **world name exactly as configured**. The
search is case-sensitive and respects the 16-character limit described above.

The first start downloads about 5.5 GB through SteamCMD, so the world takes a few
minutes to show up. Follow along with `/opt/dragonwilds/scripts/logs.sh` and wait
for `START SESSION - Success`.

## Management scripts

| Script | Description |
|--------|-------------|
| `/opt/dragonwilds/scripts/status.sh` | Status, connection details, worlds, backups and timers |
| `/opt/dragonwilds/scripts/logs.sh` | Container logs. Use `--game` for the game log |
| `/opt/dragonwilds/scripts/start.sh` | Start the server |
| `/opt/dragonwilds/scripts/stop.sh` | Stop the server, waiting for the final save |
| `/opt/dragonwilds/scripts/restart.sh` | Restart, applying `.env` changes |
| `/opt/dragonwilds/scripts/backup.sh` | Immediate backup of the worlds |
| `/opt/dragonwilds/scripts/restore.sh` | Restore a world from a backup |
| `/opt/dragonwilds/scripts/update.sh` | Check for and apply game updates |
| `/opt/dragonwilds/scripts/firewall.sh` | Reapply the rules. Use `--status` to inspect |
| `/opt/dragonwilds/scripts/first-boot.sh` | Full reconfiguration, with `--force` |

## Configuration

All server behaviour comes from `/opt/dragonwilds/.env`. The container
regenerates `DedicatedServer.ini` from those variables on every start, so
**editing the `.ini` inside `data/` has no lasting effect**, as the official
documentation itself warns.

After changing `.env`:

```bash
/opt/dragonwilds/scripts/restart.sh
```

Main variables:

| Variable | Default | Description |
|----------|---------|-------------|
| `RSDW_OWNER_ID` | (empty) | Owner's EOS Online ID. Required |
| `RSDW_WORLD_NAME` | generated | Name searched in the browser. **Max. 16 characters** |
| `RSDW_SERVER_NAME` | `letscloud-dw` | Name in the "Created By" column. **Max. 16 characters** |
| `RSDW_PORT` | `7777` | Game UDP port. Fixed, should not be changed |
| `RSDW_BEACON_PORT` | `8888` | Beacon UDP port. Required, should not be changed |
| `RSDW_PASSWORD` | generated | World password. Empty leaves it open |
| `RSDW_ADMIN_PASSWORD` | generated | Access to the Server Management screen |
| `RSDW_ADMINS` | (empty) | List of EOS IDs with admin permission |
| `DW_UPDATE_MODE` | `window` | `notify`, `window` or `immediate` |
| `DW_UPDATE_WINDOW_HOUR` | `5` | Maintenance window hour |
| `DW_KEEP_HOURLY/DAILY/WEEKLY` | `24/7/4` | Backup retention |

> **Warning:** never set a password to the literal value `random`. The official
> container reads that word as "generate a new one on every start", which would
> change the password at each restart. `first-boot.sh` blocks this value.

### 16-character limit on names

The game publishes the world name and the server name in the browser as EOS
session attributes **limited to 16 characters**, and silently truncates anything
longer. Confirmed in the server log:

```
LogNetSessionSettings: SlotName truncated to fit max length
  was[ABCDEFGHIJKLMNOPQRSTUVWXYZ] now[ABCDEFGHIJKLMNOP]
```

The local save keeps the full name, so the symptom is deceptive: the server comes
up normally, but whoever received the complete name searches for something the
browser never returns. The wizard rejects longer names in interactive mode and
truncates them with a warning in automatic mode, so that `.env`, the summary and
the browser always show the same string.

### Join code

On every start the server publishes a **join code** (format `XXXX-XXXX`), which
removes the need to search by name. It changes whenever the container is
recreated, which is why it is read from the live log:

```bash
/opt/dragonwilds/scripts/status.sh    # shows the current join code
```

It also appears in the MOTD and in `/root/dragonwilds_info.txt`.

## Firewall ports

| Port | Protocol | Service |
|------|----------|---------|
| 22 | TCP | SSH |
| 7777 | UDP | RuneScape: Dragonwilds (game port) |
| 8888 | UDP | RuneScape: Dragonwilds (beacon port) |

The default policy is `deny incoming` and `allow outgoing`. No other port is
opened.

Every change goes through `scripts/firewall.sh`, which never enables UFW without
first **confirming that the SSH port is allowed**. If the rule is missing, it
aborts with an error instead of enabling a `deny incoming` firewall that would
leave the instance unreachable. When UFW is already active, it uses `reload`
instead of disabling and re-enabling, so the session in use is not dropped. The
script also detects the real `sshd` port from `sshd_config`, in case it was
changed.

To inspect or reapply:

```bash
/opt/dragonwilds/scripts/firewall.sh --status
/opt/dragonwilds/scripts/firewall.sh
```

It is worth noting that containers with published ports are allowed by Docker
directly in iptables, bypassing UFW. The explicit UDP rule is kept anyway, so
the intent stays visible in `ufw status`.

The game uses **UDP**, and port **7777 is fixed in this image**. The official
documentation states that only a second server on the same host would move to
7778 and up, a scenario out of scope here, since the image runs one server per
VPS. Keeping the value fixed guarantees that the UFW rule, `docker-compose.yml`
and the address given to players never drift out of sync.

Besides the game port, the server needs the **beacon port (`8888/udp`, by the
game's convention of port + 1111)**. That is how the world browser advertises and
reaches the server. The [official container README](https://github.com/runescape/rsdw-dedicated)
is explicit: if `RSDW_PORT` and `RSDW_BEACON_PORT` are not reachable, the world
still appears in the list but joining fails with *"connection lost"*. That is why
both ports are published in the compose file and allowed in UFW.

## Requirements

The official documentation defines the memory per player, and the container
repository defines the absolute minimum:

| Players | RAM | Note |
|---------|-----|------|
| 2 | 4 GB | Official formula: 2 GB + 1 GB per player |
| 4 | 6 GB | |
| 6 | 8 GB | Maximum supported by the game in version 0.11 |

- CPU: 1 core minimum, 2 recommended
- Disk: the installation takes about 5.5 GB; reserve 20 GB to cover backups and
  the growth of future builds
- A 64-bit operating system is mandatory

Matching LetsCloud plans:

| Plan | Players | Note |
|------|---------|------|
| `2vcpu-4gb-80ssd` | up to 2 | Template default |
| `4vcpu-8gb-160ssd` | up to 6 | Maximum supported by the game |

Plans with 1 or 2 GB of RAM are not enough, because the official formula reserves
2 GB for the server before the first player.

## Update strategy

This is the most delicate part of the operation, because **client and server must
run the same version**. An out-of-date server simply disappears from the world
browser.

**How the container behaves.** The official image runs `app_update` on every
start, which means restarting the container **is** updating. While running, it
queries Valve's UpToDateCheck API every 30 minutes and, if
`RSDW_AUTO_STOP_ON_UPDATE=true`, terminates the process as soon as a new build
appears, relying on the restart policy to come back updated.

**Why that automatic mode is disabled.** It drops players at the exact moment
Jagex publishes a build, in the middle of a session. That is the scenario the
original requirement asks to avoid.

**What the image does instead.** `dragonwilds-update.timer` runs hourly and
`update.sh` applies this sequence of safeguards:

1. Queries Valve's API with the installed build id.
2. Only acts inside the maintenance window (`DW_UPDATE_WINDOW_HOUR`, default 5am).
3. Only acts if there is no active connection on the game UDP port.
4. Takes a **cold backup** before touching anything.
5. Recreates the container, which triggers `app_update`.
6. Confirms the server came back and logs everything to `/var/log/dragonwilds/`.

The world lives in a bind mount that is never deleted, so the update replaces
only the game binaries.

**An important, verified caveat.** At the time of writing, the UpToDateCheck API
answers `Couldn't get app info for the app specified` for appid 4019830. The
official container hits the same limit and simply keeps running, which in
practice would mean never updating. That is why `update.sh` has a fallback: when
the API cannot answer, it performs a periodic maintenance restart (default: at
most once a day, still respecting the window and the absence of players) and lets
SteamCMD decide. If it is already on the current version, `app_update` does
nothing.

Modes available in `DW_UPDATE_MODE`:

- `notify`: only writes to the log, nothing is restarted. Fully manual control
- `window`: default, updates inside the maintenance window and only when idle
- `immediate`: updates as soon as it is idle, at any time of day

To apply right away, ignoring the window and the player check:

```bash
/opt/dragonwilds/scripts/update.sh --check   # check only
/opt/dragonwilds/scripts/update.sh --now     # apply immediately
```

## Backups

`dragonwilds-backup.timer` runs every hour, at 7 minutes past. The default
retention follows the requested suggestion:

| Tier | Count | When |
|------|-------|------|
| Hourly | 24 | Every hour |
| Daily | 7 | At 4am |
| Weekly | 4 | Sunday at 4am |

A daily backup is a **hardlink** of the matching hourly one, so promoting a copy
does not duplicate disk space.

**What goes into the archive:** the worlds' `.sav` files and
`DedicatedServer.ini`, which carries the `ServerGuid`. The roughly 5.5 GB of game
installation is deliberately left out, because SteamCMD can always download it
again and including it would make hourly backups impractical.

### Does the server have to be stopped for the backup to be consistent?

Short answer: **not for the routine backup, yes for the one that precedes a
destructive operation.**

The dedicated server exposes no "flush to disk on demand" command, and the
official documentation treats backup as "copy the files from `SaveGames`". Since
the game writes the world in periodic autosaves rather than continuously, there
is a wide window between writes. The default backup is **hot** and takes
advantage of that with three precautions:

1. Before archiving, it samples the size and mtime of every `.sav` twice, 3
   seconds apart, and only proceeds when nothing changed, which indicates no
   autosave is in progress.
2. It writes to a `.partial` file and only renames at the end, so a half-written
   file never exists under a valid backup name.
3. It validates the result with `tar -tzf` and checks that there is at least one
   `.sav` inside. If validation fails, the file is discarded instead of becoming
   a useless backup. A `.sha256` accompanies each archive.

When the guarantee has to be absolute, the backup is **cold**: the container is
stopped, which forces the final save, the copy is made and the server comes back.
This is what happens automatically before every update and every restore. To
force it manually:

```bash
/opt/dragonwilds/scripts/backup.sh --cold
```

To make cold backups the default for all scheduled runs, set
`DW_BACKUP_COLD=true` in `.env`. That trades a small hourly outage for guaranteed
consistency.

### Manual backup

```bash
/opt/dragonwilds/scripts/backup.sh
/opt/dragonwilds/scripts/backup.sh --label before-testing-mod
```

Backups are kept in `/opt/dragonwilds/backups/`, on the instance's own disk.

## Restore

```bash
/opt/dragonwilds/scripts/restore.sh            # list and prompt
/opt/dragonwilds/scripts/restore.sh --list     # list only
/opt/dragonwilds/scripts/restore.sh --latest --yes
```

The process is always this:

1. Lists the available backups with size and date.
2. Takes the selection, or accepts `--file` / `--latest`.
3. Checks the `.sha256` and tests the archive's integrity **before** stopping the
   server. A corrupted archive aborts without causing damage.
4. Stops the server, waiting for the final save.
5. Creates a safety backup of the current state in `backups/pre-restore/`. If
   that backup fails, the restore is aborted and the server comes back intact.
6. Extracts to a temporary directory and only then replaces the worlds, so a
   failure halfway through does not leave `SaveGames` mixed up.
7. Reapplies `1000:1000` ownership.
8. Starts the server and confirms it came up.

The server is necessarily stopped because it loads the world into memory at start
and writes it back on the next autosave. Swapping the files with the server
running would cause the restored world to be overwritten.

## Security

- **Unprivileged container**: `no-new-privileges`, `cap_drop: ALL` and execution
  as uid 1000, without `privileged` and without access to the Docker socket
- **Minimal exposure**: only 22/tcp, 7777/udp and 8888/udp, with `deny incoming`
  as the default
- **`.env` protection**: created directly with mode `0600` and `root:root`, so
  the passwords never exist with loose permissions, not even for an instant
- **No hardcoded passwords**: everything is generated per instance with
  `openssl rand`, 20 characters with no ambiguous glyphs
- **Safe `.env` parsing**: the file is interpreted line by line instead of using
  `source`, because the values are written without quotes for docker compose. A
  password containing a space, `|` or `&` would be executed as code by `.`
- **Re-run protection**: `001_onboot` is removed both by cloud-init and by
  itself, and `first-boot.sh` checks a marker before running
- **Rotated logs**: logrotate for the scripts and for the game log, plus a size
  limit on Docker's json-file driver
- **Safe shutdown**: a 120-second `stop_grace_period`, so the world is never
  truncated by a premature SIGKILL

## Known limitations

Raised in the official documentation and in the container repository:

- A maximum of **6 concurrent players** in version 0.11 (March 2026)
- Steam invites do not connect correctly on dedicated servers
- Changing `DedicatedServer.ini` while the server is running has no effect
- The server loads the most recent `.sav` from `SaveGames` at start. If the folder
  is empty, it creates a default world
- Only the Owner can ban and unban offline players. Admins can only ban players
  who are online

## Links

- Official guide: https://dragonwilds.runescape.com/news/how-to-dedicated-servers
- Official container: https://github.com/runescape/rsdw-dedicated
- Wiki: https://dragonwilds.runescape.wiki/w/Dedicated_Servers
