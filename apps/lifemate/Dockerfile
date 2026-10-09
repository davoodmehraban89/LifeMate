# SDK pinned to the exact official Flutter revision used by CI.
# Build dependencies may need developer-side network access;
# the shipped client loads its resources from the deployment origin.
FROM node:22-bookworm-slim AS node-tools
FROM ubuntu:24.04 AS build
ARG FLUTTER_REVISION=5fc346839b5d0eef006ed8404392afb4dfae428d
ARG FLUTTER_VERSION=3.47.6
ENV PATH="/opt/flutter/bin:${PATH}"
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates curl git unzip xz-utils libglu1-mesa \
    && rm -rf /var/lib/apt/lists/*
RUN --mount=type=secret,id=build_ca \
    if [ -s /run/secrets/build_ca ]; then \
      cp /run/secrets/build_ca /usr/local/share/ca-certificates/build-proxy.crt \
      && update-ca-certificates; fi \
    && git init /opt/flutter \
    && git -C /opt/flutter remote add origin https://github.com/flutter/flutter.git \
    && git -C /opt/flutter fetch --depth 1 origin "$FLUTTER_REVISION" \
    && git -C /opt/flutter checkout --detach FETCH_HEAD \
    && git -C /opt/flutter fetch --depth 1 origin "refs/tags/$FLUTTER_VERSION:refs/tags/$FLUTTER_VERSION" \
    && test "$(git -C /opt/flutter rev-parse "refs/tags/$FLUTTER_VERSION")" = "$FLUTTER_REVISION" \
    && rm -f /opt/flutter/bin/cache/flutter.version.json \
    && flutter config --enable-web --no-analytics \
    && flutter precache --web
WORKDIR /src
COPY pubspec.yaml pubspec.lock ./
RUN flutter pub get
COPY . .
RUN flutter build web --release --no-web-resources-cdn --pwa-strategy=none

# Process only the small shipped artifact in a separate Node stage. Keeping
# Node out of the Flutter stage also avoids another SDK-sized builder snapshot.
FROM node-tools AS web-artifact
WORKDIR /artifact
COPY --from=build /src/build/web ./web
COPY tool/self_host_web.mjs ./self_host_web.mjs
RUN node self_host_web.mjs web

FROM nginx:1.28-alpine
COPY deploy/nginx.conf /etc/nginx/conf.d/default.conf
COPY deploy/security-headers.inc /etc/nginx/security-headers.inc
COPY --from=web-artifact --chown=nginx:nginx /artifact/web /usr/share/nginx/html
RUN mkdir -p /usr/share/nginx/html/downloads /etc/nginx/tls
EXPOSE 443
