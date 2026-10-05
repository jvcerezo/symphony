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

# Copy dependency configuration and resolve Dart packages
COPY pubspec.yaml pubspec.lock ./
RUN dart pub get --no-precompile

# Copy server logic and compiled web bundle
COPY server.dart ./
COPY --from=builder /app/build/web ./build/web

# Expose standard port and declare environment defaults
ENV PORT=8080
ENV WEB_DIR=build/web
EXPOSE 8080

CMD ["dart", "run", "server.dart"]
