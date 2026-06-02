FROM node:20-slim

# Install dependencies I think are useful to agents working env.
# Perhaps add e.g. "build essentials" later.
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    git \
    python3 \
    python3-pip \
    python3-venv \
    ripgrep \
    dnsutils \
    tmux \
    vim \
    procps \
    sbcl \
    iputils-ping \
    telnet \
    iproute2 \
    traceroute \
    && rm -rf /var/lib/apt/lists/*

# Install Claude using the native installer. Keep an eye on Claude docs for when
# they change this procedure.
#
# The installer is $HOME-driven (it lays the binary out under
# $HOME/.local/bin + $HOME/.local/share/claude). The build runs as root, so a
# default install lands in /root/.local — off the run-user's PATH and inside an
# unreadable 0700 dir, and the /home/node volume mount would shadow a
# ~/.local install at runtime anyway. So install into a shared /opt location
# that is outside any mounted volume and readable by any run-user, then put it
# on PATH. Runtime self-updates still land in $HOME/.local and take precedence
# via PATH order.
RUN curl -fsSL https://claude.ai/install.sh | HOME=/opt/claude bash \
    && chmod -R a+rX /opt/claude
ENV PATH="/opt/claude/.local/bin:${PATH}"

# Make sure to launch the container binding the host CWD to this workdir
WORKDIR /workspace

ENTRYPOINT ["bash", "-l", "-c", "exec claude \"$@\"", "--"]
