# Claude Code Container — Networking Notes

## Container Setup

The container is launched via `claude.sh` from the project directory you want to work in:

```bash
./claude.sh
```

Key flags used in the `podman run` command:

| Flag | Effect |
|---|---|
| `--userns=keep-id` | Maps your host UID into the container |
| `-v claude-config:/home/node` | Persistent named volume for Claude's config and memory |
| `-v $(pwd):/workspace:z` | Current host directory mounted as `/workspace` |
| `--network=claude-code-net` | Dedicated Podman network (must be pre-created) |
| `--cap-drop ALL` | No Linux capabilities |
| `--security-opt no-new-privileges` | No privilege escalation |

The Podman network `claude-code-net` must exist before running. Create it once with:

```bash
podman network create claude-code-net
```

---

## Network Isolation (Firewall)

`claude.sh` has a `firewall` subcommand that installs iptables `FORWARD` DROP rules to prevent the container from reaching your private/office subnets:

```bash
sudo ./claude.sh firewall
```

This adds rules blocking the container subnet (e.g. `10.89.5.0/24`) from forwarding to:

- `10.228.0.0/16`
- `192.168.0.0/16`
- `172.16.0.0/12`

Internet access (public IPs) is unaffected. These rules survive firewalld restarts but are lost on reboot, so re-run the `firewall` subcommand after reboots.

> **Note:** The rules use `-I` (insert) with an existence check (`-C`) so they are idempotent — safe to run multiple times.

---

## Reaching Host Services from the Container

### The virtual gateway problem

The container gets an IP in the `claude-code-net` subnet (e.g. `10.89.5.3`) with a virtual gateway at `10.89.5.1`. Despite appearances, **`10.89.5.1` is not a real IP on the host** — it is a virtual address managed by Podman's network stack. Attempting to connect to host services via `10.89.5.1` results in connection refused.

Verify: `hostname -I` on the host will not list `10.89.5.1`.

### The correct approach: `host.containers.internal`

Podman injects `host.containers.internal` into every container's `/etc/hosts`, pointing to a stable link-local address (`169.254.1.2`). This works regardless of which physical network the host is on (home, office, etc.).

```bash
# From inside the container:
curl http://host.containers.internal:5002/
```

Use `host.containers.internal` whenever the container needs to reach a service running directly on the host.

### Services in other containers (published ports)

If the target service itself runs inside a Podman container with a published port (e.g. `-p 5002:5002`), the situation depends on how that container was launched:

- **Rootless container** (`rootlessport` in `ss -tlnp`): the port is bound to the host loopback only. Reachable via `host.containers.internal` from this container only if the host's loopback is reachable, which it typically is.
- **Rootful container or host-native process** (Python3/other process directly in `ss -tlnp`): the socket is in either the host or container network namespace. If the socket is in a container namespace, Podman sets up DNAT forwarding — but this forwarding does **not** apply to hairpin traffic originating from another Podman container. Use `host.containers.internal` to reach it, as the host's INPUT chain has policy ACCEPT.

### Why the private-subnet FORWARD rules don't block host access

The iptables `FORWARD` chain handles traffic being routed *through* the host to another machine. Traffic from the container destined *for the host itself* (any of the host's own IPs) traverses the `INPUT` chain instead, which has policy `ACCEPT` and no blocking rules. This is why `host.containers.internal` works even with the protective FORWARD rules in place.

---

## Volume Backup

Claude's config and memory live in the `claude-config` named volume. Back it up with:

```bash
./claude.sh backup
```

Backups are written as timestamped `.tgz` files to `/home/niklas/containers/anthropic/claude/backup-volumes/`.

---

## Quick Reference

```bash
# First-time setup
podman network create claude-code-net

# Install firewall rules (after each reboot)
sudo ./claude.sh firewall

# Launch Claude Code in current directory
./claude.sh

# Backup Claude's config volume
./claude.sh backup

# Reach a host service from inside the container
curl http://host.containers.internal:<port>/
```
