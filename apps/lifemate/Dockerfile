FROM ghcr.io/cirruslabs/flutter:stable AS build
WORKDIR /src

COPY pubspec.yaml ./
RUN flutter pub get

COPY . .

RUN flutter build web --release \
  --dart-define=LIFEMATE_API_URL=https://lifemate-api-fn-staging.up.railway.app

RUN flutter build apk --release \
  --dart-define=LIFEMATE_API_URL=https://lifemate-api-fn-staging.up.railway.app

FROM nginx:1.27-alpine

COPY deploy/nginx.conf /etc/nginx/conf.d/default.conf
COPY --from=build /src/build/web /usr/share/nginx/html
RUN mkdir -p /usr/share/nginx/html/downloads
COPY --from=build /src/build/app/outputs/flutter-apk/app-release.apk /usr/share/nginx/html/downloads/LifeMate.apk

EXPOSE 80
