# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

This repository is a containerized execution environment for the Claude Code CLI tool. It wraps `@anthropic-ai/claude-code` in a Podman container for isolated, reproducible usage.

## Running Claude

```bash
./claude.sh
```

This script launches a Podman container interactively, mounting the current directory to `/workspace` and a persistent named volume to `/home/node` for config.

## Architecture

Three files compose the entire project:

- **`Containerfile`** — Builds the container image: `node:20-slim` base + `@anthropic-ai/claude-code` (global npm install) + system tools (`git`, `python3`, `ripgrep`, `tmux`)
- **`claude.sh`** — Shell wrapper that runs the container via Podman with `--rm -it`, `--userns=keep-id`, workspace volume mount, and passes through environment from `.env`
- **`.env`** — Contains `ANTHROPIC_API_KEY` for Claude API authentication

## Volume Mounts

| Host | Container | Purpose |
|------|-----------|---------|
| `$(pwd)` | `/workspace:z` | Current project files |
| `claude-config` (named volume) | `/home/node` | Persistent Claude config/memory |
