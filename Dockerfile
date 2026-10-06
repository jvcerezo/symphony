# Stage 1: Build Flutter Web application
FROM ghcr.io/cirruslabs/flutter:stable AS builder

WORKDIR /app
COPY pubspec.yaml pubspec.lock ./
RUN flutter pub get

COPY . .
RUN flutter build web --release

# Stage 2: Minimal Dart runtime container
FROM dart:stable AS runner

WORKDIR /app

# Install python3, certificates, and yt-dlp for YouTube audio stream proxying
RUN apt-get update && apt-get install -y --no-install-recommends \
    python3 \
    python3-pip \
    ca-certificates \
    curl \
    && rm -rf /var/lib/apt/lists/* \
    && (pip3 install --no-cache-dir --break-system-packages yt-dlp 2>/dev/null || pip3 install --no-cache-dir yt-dlp 2>/dev/null || true)

# Copy dependency configuration and resolve Dart packages for headless server
COPY pubspec.server.yaml ./pubspec.yaml
RUN dart pub get --no-precompile

# Copy server logic and compiled web bundle
COPY server.dart ./
COPY --from=builder /app/build/web ./build/web

# Expose standard port and declare environment defaults
ENV PORT=8080
ENV WEB_DIR=build/web
EXPOSE 8080

CMD ["dart", "run", "server.dart"]
