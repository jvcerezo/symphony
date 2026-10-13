# Symphony Discord bot: Node + ffmpeg + yt-dlp, plus a PO token helper that
# gets cloud servers past YouTube's "confirm you're not a bot" check.

ARG POT_VERSION=2.0.2

# The PO token helper (bgutil-ytdlp-pot-provider), built from its release.
FROM node:22-slim AS pot
ARG POT_VERSION
RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates curl \
    && rm -rf /var/lib/apt/lists/*
WORKDIR /pot
RUN curl -fsSL "https://github.com/Brainicism/bgutil-ytdlp-pot-provider/archive/refs/tags/${POT_VERSION}.tar.gz" \
    | tar -xz --strip-components=2 "bgutil-ytdlp-pot-provider-${POT_VERSION}/server" \
    && npm ci --no-audit --no-fund \
    && npx tsc \
    && npm prune --omit=dev --no-audit --no-fund

FROM node:22-slim
ARG POT_VERSION

RUN apt-get update && apt-get install -y --no-install-recommends ffmpeg ca-certificates curl \
    && rm -rf /var/lib/apt/lists/*

USER node
WORKDIR /home/node/bot

# The standalone yt-dlp build needs no Python. It sits in a folder the bot
# owns so it can update itself on every start (YouTube changes often).
# Built for x86 and ARM servers (such as Oracle's free Ampere machines).
ARG TARGETARCH
RUN mkdir -p /home/node/bin /home/node/.yt-dlp/plugins \
    && case "$TARGETARCH" in arm64) build=yt-dlp_linux_aarch64 ;; *) build=yt-dlp_linux ;; esac \
    && curl -fsSL -o /home/node/bin/yt-dlp "https://github.com/yt-dlp/yt-dlp/releases/latest/download/$build" \
    && chmod +x /home/node/bin/yt-dlp \
    && curl -fsSL -o /home/node/.yt-dlp/plugins/bgutil-ytdlp-pot-provider.zip \
       "https://github.com/Brainicism/bgutil-ytdlp-pot-provider/releases/download/${POT_VERSION}/bgutil-ytdlp-pot-provider.zip"
ENV PATH="/home/node/bin:${PATH}"

COPY --from=pot --chown=node:node /pot /home/node/pot
ENV POT_SERVER_SCRIPT=/home/node/pot/build/main.js

COPY --chown=node:node package.json package-lock.json ./
RUN npm ci --omit=dev
COPY --chown=node:node src ./src

ENV NODE_ENV=production
CMD ["sh", "-c", "yt-dlp -U >/dev/null 2>&1 || true; exec node src/index.js"]
