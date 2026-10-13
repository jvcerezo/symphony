# Symphony Discord bot: Node + ffmpeg + yt-dlp.
FROM node:22-slim

RUN apt-get update && apt-get install -y --no-install-recommends ffmpeg ca-certificates curl \
    && rm -rf /var/lib/apt/lists/*

USER node
WORKDIR /home/node/bot

# The standalone yt-dlp build needs no Python. It sits in a folder the bot
# owns so it can update itself on every start (YouTube changes often).
RUN mkdir -p /home/node/bin \
    && curl -fsSL -o /home/node/bin/yt-dlp https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp_linux \
    && chmod +x /home/node/bin/yt-dlp
ENV PATH="/home/node/bin:${PATH}"

COPY --chown=node:node package.json package-lock.json ./
RUN npm ci --omit=dev
COPY --chown=node:node src ./src

ENV NODE_ENV=production
CMD ["sh", "-c", "yt-dlp -U >/dev/null 2>&1 || true; exec node src/index.js"]
