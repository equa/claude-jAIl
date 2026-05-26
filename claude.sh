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
    if ! podman network exists $1; then
        echo "Network $1 does not exist. Create it first with:"
        echo "  podman network create $1"
        exit 1
    fi
}

function get_subnet()
{
    local __subnet__
    __subnet__=$(podman network inspect $1 | jq -r '.[]|.subnets|.[0]|.subnet')
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
    # Firewall blocking of protected subnets from container
    # Requires root!
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

function backup()
{
    mkdir -p $CLAUDE_VOLUME_BACKUP_DIR
    BACKUP_FILE="$CLAUDE_VOLUME_BACKUP_DIR/$(date +%Y%m%d-%H%M%S.tgz)"
    podman volume export $CLAUDE_VOLUME | gzip > $BACKUP_FILE
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

PODMAN_COMPOSE_PROVIDER=podman

podman run -it --rm \
  --userns=keep-id \
  -v $CLAUDE_VOLUME:/home/node \
  -v $(pwd):/workspace:z \
  --security-opt no-new-privileges \
  --network=$CLAUDE_NET \
  --cap-drop ALL \
  -w /workspace \
  claude-code $@
