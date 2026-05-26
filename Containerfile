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
    sbcl \
    && rm -rf /var/lib/apt/lists/*

# Install claude using native installer. Keep an eye on Claude docs for when
# they change this procedure.
RUN curl -fsSL https://claude.ai/install.sh | bash

# Make sure to launch the container binding the host CWD to this workdir
WORKDIR /workspace

ENTRYPOINT ["bash", "-l", "-c", "exec claude \"$@\"", "--"]
