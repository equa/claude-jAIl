#Requires -Version 5.1
<#
.SYNOPSIS
    Run Claude Code in an isolated Podman container on Windows 11.

.DESCRIPTION
    PowerShell port of claude.sh for Podman Desktop on Windows.

    Podman Desktop runs containers inside a WSL2-backed Podman machine, so the
    `podman` CLI behaves like it does on Linux. The Containerfile is reused
    unchanged; this launcher mounts the current directory as /workspace and a
    named volume as /home/node so Claude's config and memory persist.

    The subnet firewall from the Linux version is NOT implemented here: it
    relied on host iptables FORWARD rules, which do not exist on Windows. See
    the "Phase 2 — firewall" section of the README for the planned approach.

.EXAMPLE
    .\claude.ps1
    Launch Claude Code in the current directory.

.EXAMPLE
    .\claude.ps1 --continue
    Pass-through arguments go straight to the claude binary in the container.

.EXAMPLE
    .\claude.ps1 backup
    Export the claude-config volume to a timestamped .tar in backup-volumes\.
#>

[CmdletBinding()]
param(
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$PassThru = @()
)

$ErrorActionPreference = 'Stop'

# ------------------------------------------------------------------------------
# Configuration
# ------------------------------------------------------------------------------

$ClaudeVolume = 'claude-config'
$ClaudeNet    = 'claude-code-net'
$ScriptDir    = $PSScriptRoot
$BackupDir    = if ($env:CLAUDE_BACKUP_DIR) { $env:CLAUDE_BACKUP_DIR } else { Join-Path $ScriptDir 'backup-volumes' }

# Public DNS for the container. The system resolver may be on a private subnet
# that is unreachable once egress filtering is in place; a public resolver
# keeps name resolution working. Override via the CONTAINER_DNS env var.
$ContainerDns = if ($env:CONTAINER_DNS) { $env:CONTAINER_DNS } else { '8.8.8.8' }

# Container runtime. Default is podman (rootless inside the Podman machine).
# Override with CTR=docker for Docker Desktop.
$Runtime = if ($env:CTR) { $env:CTR } else { 'podman' }

# ------------------------------------------------------------------------------
# Helpers
# ------------------------------------------------------------------------------

function Invoke-Runtime {
    # Run the configured container runtime, splitting CTR on whitespace so a
    # multi-word value (e.g. "podman --log-level debug") still works.
    $parts = $Runtime -split '\s+'
    & $parts[0] @($parts[1..($parts.Length - 1)]) @args
}

function Test-Subnet {
    param([string]$Net)
    Invoke-Runtime network exists $Net | Out-Null
    if ($LASTEXITCODE -ne 0) {
        Write-Host "Network $Net does not exist. Create it first with:"
        Write-Host "  $Runtime network create $Net"
        exit 1
    }
}

function Show-Readme {
    Get-ChildItem -Path $ScriptDir -Filter 'README*.md' | ForEach-Object {
        Get-Content $_.FullName | Write-Output
    }
    exit 0
}

function Invoke-Backup {
    if (-not (Test-Path $BackupDir)) {
        New-Item -ItemType Directory -Path $BackupDir | Out-Null
    }
    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $backupFile = Join-Path $BackupDir "$stamp.tar"
    Invoke-Runtime volume export $ClaudeVolume -o $backupFile
    if ($LASTEXITCODE -ne 0) {
        Write-Host 'Backup failed.'
        exit 1
    }
    Write-Host "Backup written to $backupFile"
    exit 0
}

# ------------------------------------------------------------------------------
# Subcommands
# ------------------------------------------------------------------------------

$subcommand = if ($PassThru.Count -gt 0) { $PassThru[0] } else { '' }

switch ($subcommand) {
    'firewall' {
        Write-Host 'The subnet firewall is not implemented on Windows.'
        Write-Host 'It relied on host iptables FORWARD rules, which do not exist here.'
        Write-Host 'See the "Phase 2 - firewall" section of the README for the planned approach.'
        exit 1
    }
    'backup' { Invoke-Backup }
    { $_ -in @('help', '-h') } { Show-Readme }
}

# ------------------------------------------------------------------------------
# Launch
# ------------------------------------------------------------------------------

# Refuse to run from the user's home directory: the whole point is to mount a
# specific project, and mounting the entire profile is almost never intended.
if ((Get-Location).Path -eq (Resolve-Path $HOME).Path) {
    Write-Host 'Do not run in home folder!'
    exit 1
}

Test-Subnet $ClaudeNet

# Notes on differences from the Linux launcher (claude.sh):
#   * No --user / --userns: the Podman machine maps host file access for us.
#   * No :z on the workspace mount: that is an SELinux relabel, Linux-only.
#   * No firewall: see the firewall subcommand above and the README.
$runArgs = @(
    'run', '-it', '--rm',
    '--dns', $ContainerDns,
    '-v', "${ClaudeVolume}:/home/node",
    '-v', "$((Get-Location).Path):/workspace",
    '--security-opt', 'no-new-privileges',
    '--network', $ClaudeNet,
    '--cap-drop', 'ALL',
    '-w', '/workspace',
    'claude-code'
) + $PassThru

Invoke-Runtime @runArgs
exit $LASTEXITCODE
