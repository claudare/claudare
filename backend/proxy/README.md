# Proxy server

A single threaded development server for WebSocket proxy replication.
`GET /health` provides a health check. You cannot not run multiple instances of
this server.

The server does not provide authentication or encryption.

Nightly downloads are available from [Proxy releases][releases].

## Run locally

Run from this directory; the default port is `7000`:

```sh
PORT=7000 fvm dart run bin/main.dart
```

## Docker installation

Only nightly Linux x64 images are available.

```sh
docker run -d --name claudare-proxy --restart unless-stopped \
  -p 7000:7000 ghcr.io/claudare/proxy:nightly
```

[releases]: https://github.com/claudare/claudare/releases/tag/proxy/nightly
