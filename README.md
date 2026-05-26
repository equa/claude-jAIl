# Claude Code — Containerized Setup

A minimal Podman-based wrapper that runs the [Claude Code](https://claude.ai/code) CLI in an
isolated container. Each project gets its own workspace mount; Claude's
configuration and memory persist in a named volume across sessions.

---

## Overview

```
Containerfile     — builds the claude-code image
claude.sh         — launch script (run, firewall, backup, help)
.env              — your ANTHROPIC_API_KEY (not committed)
```

The default mode is **rootless Podman**:
- `--userns=keep-id` maps the host UID into the container so file ownership is correct
- A dedicated network (`claude-code-net`) with optional iptables firewall rules
- All Linux capabilities dropped, no privilege escalation

The runtime is controlled by the `CTR` environment variable and defaults to `podman`.
See [Container Runtime](#container-runtime-ctr) for rootful Podman and Docker options.

---

## Prerequisites

| Tool | Purpose |
|------|---------|
| [Podman](https://podman.io/) | Container runtime (rootless) |
| `jq` | Parsing network info in `claude.sh` |
| `sudo` + `iptables` | Optional: subnet firewall rules |

On Fedora/RHEL:
```bash
sudo dnf install podman jq
```

On Debian/Ubuntu:
```bash
sudo apt install podman jq
```

---

## First-time Setup

### 1. Authenticate with Claude

There are two ways to authenticate, depending on your plan:

**API key** (individual/API plans):
```bash
cp .env.example .env
# Edit .env and paste your ANTHROPIC_API_KEY
```
`.env` is gitignored and never committed.

**Web login** (Claude.ai Pro / Team plans):

Skip the `.env` step. After the container starts, run `/login` inside Claude
and select the Claude.ai account option. You will be given a URL to open in a
browser.

> **Important:** Open the URL in an **incognito/private browser window**. If
> your regular browser is logged into a different Claude account (personal vs
> team, or a different organisation), the auth URL will silently use that
> session and redirect you to the sign-up page instead of showing the
> authorisation code. Incognito gives a clean session tied to whichever account
> you log into there.

Paste the code back into Claude when prompted. Login state is stored in the
`claude-config` volume and persists across sessions.

### 2. Build the container image

```bash
# Rootless (default):
podman build -t claude-code .

# Rootful (recommended for effective firewall isolation):
sudo podman build -t claude-code .
```

This installs Claude Code via the official installer and adds common
development tools (`git`, `python3`, `ripgrep`, `tmux`, `vim`, …).

> **Note:** If your system DNS is on a private subnet (e.g. `10.x.x.x`) and
> you are building rootful with firewall rules active, the build container
> cannot reach the DNS server. Pass a public DNS server explicitly:
> ```bash
> sudo podman build --dns 8.8.8.8 -t claude-code .
> ```

### 4. Create the container network

```bash
# Rootless:
podman network create claude-code-net

# Rootful:
sudo podman network create claude-code-net
```

This only needs to be done once. The network persists across reboots.

### 5. (Recommended) Install firewall rules

```bash
sudo ./claude.sh firewall
```

This adds iptables `FORWARD DROP` rules that prevent the container from
reaching your private/office subnets while leaving internet access intact.

> **Important:** iptables `FORWARD` rules are only effective with a **rootful**
> runtime (`CTR="sudo podman"` or `CTR=docker`). With rootless Podman, container
> traffic is handled by `pasta` in user space and bypasses the FORWARD chain
> entirely — the rules will be present but have no effect.

> **Note:** These rules are not persistent across reboots. Re-run after each reboot,
> or add it to a startup script / systemd unit.

---

## Daily Use

**Always run `claude.sh` from the project directory you want to work in.**
The current directory is mounted as `/workspace` inside the container.

```bash
# Launch Claude Code in the current directory
./claude.sh

# Or with an alias (add to ~/.bashrc or ~/.zshrc):
alias claude='/path/to/this/repo/claude.sh'
```

Any arguments after `./claude.sh` that don't match a subcommand are passed
straight through to the `claude` binary inside the container:

```bash
./claude.sh --resume <session-id>   # resume a specific session
./claude.sh --continue              # continue the most recent session
./claude.sh --model claude-opus-4-7 # override the model
```

Claude's configuration and memory live in the `claude-config` named volume
and persist across sessions regardless of which project you launch from.

---

## Subcommands

```
./claude.sh              Launch Claude Code in the current directory
./claude.sh firewall     Install iptables rules to isolate the container network
./claude.sh backup       Export the claude-config volume to a timestamped .tgz
./claude.sh help         Print this README
./claude.sh -h           Same as help
```

### Backup

```bash
./claude.sh backup
```

Exports the `claude-config` volume (config, memory, project state) to a
timestamped `.tgz` in the `backup-volumes/` directory next to `claude.sh`.

You can override the destination:

```bash
CLAUDE_BACKUP_DIR=/mnt/nas/backups ./claude.sh backup
```

---

## Networking Notes

### Reaching host services from inside the container

The container's virtual gateway (`10.x.x.1`) is not a real host IP. Use the
hostname Podman injects into every container instead:

```bash
# From inside the container:
curl http://host.containers.internal:<port>/
```

This works regardless of which physical network the host is on.

### Firewall details

The `firewall` subcommand blocks `FORWARD` traffic from the container subnet
to these private ranges by default:

```
10.228.0.0/16   192.168.0.0/16   172.16.0.0/12   10.81.0.0/16
```

Edit the `PROTECTED_SUBNETS` variable at the top of `claude.sh` to match
your network. Internet access (public IPs) is unaffected.

See [README-claude-code-networking.md](README-claude-code-networking.md) for
a deeper explanation of how hairpin routing, loopback, and host services interact.

---

## Volume Reference

| Host | Container | Purpose |
|------|-----------|---------|
| `claude-config` (named volume) | `/home/node` | Persistent Claude config & memory |
| `$(pwd)` | `/workspace` | Your project files |

To inspect the volume:

```bash
podman volume inspect claude-config
```

To remove it (deletes all Claude memory and config!):

```bash
podman volume rm claude-config
```

---

## Container Runtime (`CTR`)

The `CTR` environment variable selects the container runtime. It defaults to
`podman` (rootless). Override it per-invocation or export it in your shell profile.

| Value | Mode | Firewall effective? |
|-------|------|-------------------|
| `podman` (default) | Rootless Podman | ✗ — pasta bypasses FORWARD |
| `sudo podman` | Rootful Podman | ✓ |
| `docker` | Docker (rootful by default) | ✓ |

```bash
# Rootless (default — simpler, but firewall rules have no effect):
./claude.sh

# Rootful Podman (firewall works, image/volume/network must be built as root):
CTR="sudo podman" ./claude.sh

# Docker:
CTR=docker ./claude.sh
```

For rootful Podman, build the image and create the network as root first (one time):

```bash
sudo podman build -t claude-code .
sudo podman network create claude-code-net
```

### Migrating an existing volume from rootless to rootful

The rootless and rootful volume stores are separate. To carry over your existing
Claude config and memory:

```bash
# 1. Create the volume in the rootful store
sudo podman volume create claude-config

# 2. Pipe the contents across (no temp file needed)
podman volume export claude-config | sudo podman volume import claude-config -
```

After importing, the volume contents will be owned by root because the import
ran as root. The container process runs as the `node` user and cannot write to
its own home directory. Fix ownership with a throwaway container:

```bash
sudo podman run --rm -v claude-config:/home/node node:20-slim \
  chown -R node:node /home/node
```

Rootful and rootless Podman are fully independent — separate image stores,
volumes, and networks. Switching one container to rootful has no effect on
any other rootless Podman work on the same machine.

---

## Customization

The top of `claude.sh` exposes the main configuration variables:

```bash
CTR=podman                         # container runtime (podman / sudo podman / docker)
CLAUDE_VOLUME=claude-config        # named volume for Claude's home
CLAUDE_NET=claude-code-net         # container network name
PROTECTED_SUBNETS="..."            # subnets blocked by the firewall subcommand
CONTAINER_DNS=8.8.8.8             # DNS used inside the container
```

If your system DNS is reachable from the container (i.e. not on a protected
subnet), you can restore it with `CONTAINER_DNS=<your-dns-ip> ./claude.sh`.

`CLAUDE_BACKUP_DIR` can be set as an environment variable (see [Backup](#backup) above).

The `Containerfile` is intentionally lean. Add system packages to the `apt-get`
block if your workflow requires additional tools.
