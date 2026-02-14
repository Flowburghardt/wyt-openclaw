FROM node:22-bookworm

# Install Bun (required for build scripts)
RUN curl -fsSL https://bun.sh/install | bash
ENV PATH="/root/.bun/bin:${PATH}"

RUN corepack enable

WORKDIR /app

ARG OPENCLAW_DOCKER_APT_PACKAGES=""
RUN if [ -n "$OPENCLAW_DOCKER_APT_PACKAGES" ]; then \
      apt-get update && \
      DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends $OPENCLAW_DOCKER_APT_PACKAGES && \
      apt-get clean && \
      rm -rf /var/lib/apt/lists/* /var/cache/apt/archives/*; \
    fi

# Skill dependencies: summarize, obsidian-cli, uv
RUN npm install -g @steipete/summarize && \
    curl -sL https://github.com/Yakitrak/notesmd-cli/releases/download/v0.3.0/notesmd-cli_0.3.0_linux_amd64.tar.gz | tar xz -C /usr/local/bin && \
    mv /usr/local/bin/notesmd-cli /usr/local/bin/obsidian-cli && \
    chmod +x /usr/local/bin/obsidian-cli && \
    curl -LsSf https://astral.sh/uv/install.sh | env INSTALLER_NO_MODIFY_PATH=1 sh && \
    cp /root/.local/bin/uv /usr/local/bin/uv && \
    cp /root/.local/bin/uvx /usr/local/bin/uvx && \
    chmod +x /usr/local/bin/uv /usr/local/bin/uvx

COPY package.json pnpm-lock.yaml pnpm-workspace.yaml .npmrc ./
COPY ui/package.json ./ui/package.json
COPY patches ./patches
COPY scripts ./scripts

RUN pnpm install --frozen-lockfile

COPY . .
RUN pnpm build
# Force pnpm for UI build (Bun may fail on ARM/Synology architectures)
ENV OPENCLAW_PREFER_PNPM=1
RUN pnpm ui:build

ENV NODE_ENV=production

# Allow non-root user to write temp files during runtime/tests.
RUN chown -R node:node /app

# Security hardening: Run as non-root user
# The node:22-bookworm image includes a 'node' user (uid 1000)
# This reduces the attack surface by preventing container escape via root privileges
# Allow node user to traverse /root/ for Coolify bind-mounted config at /root/.clawdbot
RUN chmod 755 /root
USER node

# Coolify/Docker: Bind to LAN interface on configured port.
# Upstream default is loopback-only with --allow-unconfigured.
CMD ["node", "openclaw.mjs", "gateway", "--bind", "lan", "--port", "18789"]
