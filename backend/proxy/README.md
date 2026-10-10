# Proxy server

Development server for direct and group-broadcast WebSocket messages. Connect
at `/` with nonempty `Claudare-Actor` and `Claudare-Group` headers. Each actor
can connect once. `GET /health` provides a health check.

Run from this directory; the default port is `7000`:

```sh
PORT=7000 fvm dart run bin/main.dart
```

The server does not provide authentication, encryption, or durable message
storage.

## Linux installation

Only nightly builds are available as `proxy-nightly-linux-x64.tar.gz`
from [Proxy Nightly][proxy-nightly].

[proxy-nightly]:
  https://github.com/claudare/claudare/releases/tag/proxy/nightly
