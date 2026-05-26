#!/bin/bash

if [[ $(pwd) == $(realpath $HOME) ]]
then
    echo "Do not run in home folder!"
    exit 1
fi

CLAUDE_VOLUME=claude-config
CLAUDE_NET=claude-code-net
SCRIPT_DIR=$(dirname "$(realpath "$0")")
CLAUDE_VOLUME_BACKUP_DIR=${CLAUDE_BACKUP_DIR:-$SCRIPT_DIR/backup-volumes}

PROTECTED_SUBNETS="10.228.0.0/16 10.81.0.0/16 192.168.0.0/16 172.16.0.0/12"

# Container runtime. Default is rootless Podman.
# Override via environment variable:
#   CTR="sudo podman" ./claude.sh   — rootful Podman (iptables FORWARD works)
#   CTR=docker ./claude.sh          — Docker
CTR=${CTR:-podman}

# User mapping into the container.
# Rootless Podman: --userns=keep-id maps the host UID directly.
# Rootful Podman / Docker: pass the UID explicitly via --user.
# id -u / id -g reflect the calling user even when CTR contains sudo.
if [[ "$CTR" == "podman" ]]; then
    USER_MAP="--userns=keep-id"
else
    USER_MAP="--user $(id -u):$(id -g)"
fi

# ------------------------------------------------------------------------------


function show_readme()
{
    local __dir__
    __dir__=$(dirname $(realpath $0))
    for f in $__dir__/README*.md
    do
        cat $f
    done
    exit 0
}

function check_subnet()
{
    if ! $CTR network exists $1; then
        echo "Network $1 does not exist. Create it first with:"
        echo "  $CTR network create $1"
        exit 1
    fi
}

function get_subnet()
{
    local __subnet__
    __subnet__=$($CTR network inspect $1 | jq -r '.[]|.subnets|.[0]|.subnet')
    if [[ "${__subnet__:0:2}" == 10 ]]
    then
        echo $__subnet__
    else
        echo "Could not find container subnet. Exiting!"
        exit 1
    fi
}

function protect_subnets()
{
    # Firewall blocking of protected subnets from container.
    # Only effective when CTR uses a rootful runtime (sudo podman / docker).
    # Requires sudo for iptables.
    local __subnet__
    __subnet__=$(get_subnet $1)
    for subnet in $PROTECTED_SUBNETS
    do
        echo "iptables dropping forwards from $__subnet__ to $subnet"
        sudo iptables -C FORWARD -s "$__subnet__" -d "$subnet" -j DROP 2>/dev/null \
        || sudo iptables -I FORWARD -s "$__subnet__" -d "$subnet" -j DROP
        [[ "$?" == 0 ]] || { echo "iptables command failed"; exit 1; }
    done
    echo -e "Subnets protection done."
}

function firewall_active()
{
    # Returns 0 if all DROP rules are in place, 1 if any are missing.
    # Read-only — does not modify iptables.
    local __subnet__
    __subnet__=$(get_subnet $1)
    for subnet in $PROTECTED_SUBNETS
    do
        sudo iptables -C FORWARD -s "$__subnet__" -d "$subnet" -j DROP 2>/dev/null \
            || return 1
    done
    return 0
}

function backup()
{
    mkdir -p $CLAUDE_VOLUME_BACKUP_DIR
    BACKUP_FILE="$CLAUDE_VOLUME_BACKUP_DIR/$(date +%Y%m%d-%H%M%S.tgz)"
    $CTR volume export $CLAUDE_VOLUME | gzip > $BACKUP_FILE
    exit 0
}

# ------------------------------------------------------------------------------

case "$1" in
    "firewall")
        check_subnet $CLAUDE_NET
        protect_subnets $CLAUDE_NET
        exit 0
        ;;
    "backup")
        backup
        ;;
    "help"|"-h")
        show_readme
        exit 0
        ;;
esac


# ------------------------------------------------------------------------------


check_subnet $CLAUDE_NET

# Warn if the firewall rules are not in place.
# Note: iptables FORWARD rules are only effective with a rootful runtime
# (CTR="sudo podman" or CTR=docker). With rootless Podman the rules are
# present but bypassed — see README for details.
# Run  ./claude.sh firewall  (requires sudo) to install them.
if ! firewall_active $CLAUDE_NET
then
    echo "WARNING: Firewall rules are not active. Run: sudo ./claude.sh firewall"
    read -p "Or should we try to set it up immediately? [y/n]: " ans
    if [[ "$ans" =~ ^(y|Y|yes|YES)$ ]]
    then
        protect_subnets $CLAUDE_NET || exit 1
        sleep 1
    fi
fi

$CTR run -it --rm \
  $USER_MAP \
  -v $CLAUDE_VOLUME:/home/node \
  -v $(pwd):/workspace:z \
  --security-opt no-new-privileges \
  --network=$CLAUDE_NET \
  --cap-drop ALL \
  -w /workspace \
  claude-code "$@"
