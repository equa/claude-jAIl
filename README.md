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

The container runs rootless via Podman with:
- `--userns=keep-id` so file ownership inside the container matches your host user
- A dedicated network (`claude-code-net`) with optional iptables firewall rules
- All Linux capabilities dropped, no privilege escalation

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

### 1. Get your Anthropic API key

Sign up at <https://console.anthropic.com/> and create an API key.

### 2. Create `.env`

```bash
cp .env.example .env
# Edit .env and paste your key
```

`.env` is gitignored and never committed.

### 3. Build the container image

```bash
podman build -t claude-code .
```

This installs Claude Code via the official installer and adds common
development tools (`git`, `python3`, `ripgrep`, `tmux`, `vim`, …).

### 4. Create the Podman network

```bash
podman network create claude-code-net
```

This only needs to be done once. The network persists across reboots.

### 5. (Recommended) Install firewall rules

```bash
sudo ./claude.sh firewall
```

This adds iptables `FORWARD DROP` rules that prevent the container from
reaching your private/office subnets while leaving internet access intact.
See [Networking Notes](#networking-notes) and
[README-claude-code-networking.md](README-claude-code-networking.md) for details.

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

## Customization

The top of `claude.sh` exposes the main configuration variables:

```bash
CLAUDE_VOLUME=claude-config        # named volume for Claude's home
CLAUDE_NET=claude-code-net         # Podman network name
PROTECTED_SUBNETS="..."            # subnets blocked by the firewall subcommand
```

`CLAUDE_BACKUP_DIR` can be set as an environment variable (see [Backup](#backup) above).

The `Containerfile` is intentionally lean. Add system packages to the `apt-get`
block if your workflow requires additional tools.
