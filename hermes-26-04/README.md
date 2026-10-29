# Hermes Agent One-Click (Ubuntu 26.04)

LetsCloud one-click image with Nous Research's
[Hermes Agent](https://hermes-agent.nousresearch.com) pre-installed, ready for
the LLM provider to be configured on the first login.

The official installer runs during the build, so the instance comes up with every
dependency already resolved (a Python runtime pinned through `uv`, Node.js and
the agent checkout).

## What the image includes

- Hermes Agent installed from the official installer (`stable` channel)
- Build dependencies: `ca-certificates`, `curl`, `git`, `gnupg`,
  `lsb-release`, `sudo`, `software-properties-common`
- A `/usr/local/bin/hermes` symlink usable from any shell and from cloud-init
- MOTD with getting-started instructions
- The `hermes setup --portal` wizard triggered on the first login
- A first-boot systemd unit that validates the launcher

## Structure

```text
hermes-26-04/
├── hermes-26-04.pkr.hcl                 Packer template
├── scripts/
│   ├── 011-hermes.sh                    Hermes Agent installation
│   └── 900-cleanup.sh                   Cleanup before the snapshot
└── files/
    ├── etc/profile.d/hermes-first-login.sh
    │                                     Triggers the wizard on the 1st login
    ├── etc/systemd/system/hermes-firstboot.service
    │                                     Per-instance preparation
    ├── etc/update-motd.d/99-startup     Welcome message
    ├── opt/hermes/first-boot.sh         First-boot work
    └── opt/hermes/first-login.sh        Configuration wizard
```

## Ubuntu 26.04 specifics on LetsCloud

The `ubuntu-26.04-x86_64` base image **does not ship cloud-init**. During the
build, Packer logs `cloud-init not found; continuing`. Two consequences shaped
the design of this image:

**1. There is no `per-instance` hook.** The
`/var/lib/cloud/scripts/per-instance/001_onboot` file used by the other images
would never run. Per-instance work was moved to the
[hermes-firstboot.service](./files/etc/systemd/system/hermes-firstboot.service)
unit, which runs [first-boot.sh](./files/opt/hermes/first-boot.sh) exactly once,
guarded by the `/var/lib/hermes/first-boot.done` marker.

**2. `018-force-ssh.sh` cannot be used.** The shared script appends a
`Match User root` block with `ForceCommand` to `sshd_config`, and every other
image removes it in `001_onboot`. Without cloud-init nothing would remove it,
and **root would be permanently locked out of the VPS**. Since there is nothing
to wait for on first boot here, because the agent is installed in full during
the build, the guard was simply dropped from the script list in the
[template](./hermes-26-04.pkr.hcl).

## Automatic configuration on the first login

The agent does nothing useful until an LLM provider is configured, and that step
requires a terminal, so it can run neither during the build nor from cloud-init.
That is why [hermes-first-login.sh](./files/etc/profile.d/hermes-first-login.sh)
is sourced by `/etc/profile` in every login shell and runs
[first-login.sh](./files/opt/hermes/first-login.sh), which calls
`hermes setup --portal` right after the MOTD.

The wizard is only triggered when all of these conditions hold:

| Condition | Reason |
| --- | --- |
| Interactive shell with a TTY | The wizard is interactive |
| `id -u` = `0` | The installation lives in `/root` |
| `/var/lib/hermes/first-login.done` does not exist | It has already been completed |
| `HERMES_SKIP_FIRST_LOGIN` empty | Manual escape hatch |

The `/var/lib/hermes/first-login.done` marker is created **only** when
`hermes setup --portal` finishes successfully: a `Ctrl+C` or a failure leaves the
agent unusable, so the wizard is offered again on the next login.
[900-cleanup.sh](./scripts/900-cleanup.sh) and
[first-boot.sh](./files/opt/hermes/first-boot.sh) remove the marker so it is
never inherited by the snapshot.

To skip it:

```bash
HERMES_SKIP_FIRST_LOGIN=1 ssh root@IP    # this session only
touch /var/lib/hermes/first-login.done   # permanently
```

## Where Hermes is installed

The official installer is **not** system-wide: it unpacks into
`$HERMES_HOME/hermes-agent` and publishes the launcher in `~/.local/bin`, adding
that directory to `PATH` only through `~/.bashrc` and `~/.profile`.

Since neither Packer's non-interactive shell nor cloud-init reads those files,
[011-hermes.sh](./scripts/011-hermes.sh) resolves the launcher by absolute path
and creates the symlink:

| Path | Contents |
| --- | --- |
| `/root/.hermes/hermes-agent` | Agent checkout and runtime |
| `/root/.hermes/config.yaml` | Agent configuration |
| `/usr/local/bin/hermes` | Symlink used by shells and cloud-init |
| `/opt/hermes/README` | Installation notes on the instance itself |

Because the installation lives in `/root`, **Hermes must be run as root**. To
enable another user, reinstall under that user's `HOME`.

## How to build

```bash
./build.sh hermes-26-04                  # full build
./build.sh hermes-26-04 --validate-only  # validate the template only
```

[build.sh](../build.sh) reads the API token from `~/.letscloud_token` (mode
`600`). Never place the token in files inside the repository.

Build parameters:

| Parameter | Value |
| --- | --- |
| `location_slug` | `sao2` |
| `plan_slug` | `1vcpu-2gb-50ssd` |
| `image_slug` | `ubuntu-26.04-x86_64` |
| `snapshot_name` | `hermes-26-04` |

### Snapshot integrity

The snapshot is taken from the block device, not from the page cache of the
running kernel. Without an explicit `sync`, any file written at the end of the
build can land in the image with the right size but a tail full of null bytes.

This is not hypothetical: the first build of this image lost the end of
`/etc/ssh/sshd_config` in exactly this way, because the only `sync` calls in
[900-cleanup.sh](./scripts/900-cleanup.sh) were inside the zerofill fallback
branch and, with `fstrim` succeeding, were never reached. The script now runs
`sync` before `fstrim` and again at the end.

## How to use after deployment

Connect over SSH as `root`. The `hermes setup --portal` wizard opens
automatically; once it finishes, start the agent:

```bash
hermes                  # start the agent
```

If the wizard was skipped, run it manually:

```bash
hermes setup --portal   # portal-guided wizard
```

Manual configuration:

```bash
hermes model           # LLM provider and model
hermes tools           # enabled tools
hermes gateway setup    # messaging platforms
hermes setup            # full wizard
```

Diagnostics:

```bash
hermes doctor
```

The interactive steps (`setup`, `gateway`) are skipped during the build because
they require a terminal, which is exactly why `hermes setup --portal` is
triggered on the first login.

## Minimum requirements

The plan used for the build is `1vcpu-2gb-50ssd`. The agent downloads its own
Python runtime and Node.js dependencies, so 2 GB of RAM is the recommended
minimum; move up to `2vcpu-4gb-80ssd` if you plan to use the gateway and local
models.

## Links

- [Installation documentation](https://hermes-agent.nousresearch.com/docs/getting-started/installation)
- [Hermes Agent website](https://hermes-agent.nousresearch.com)
