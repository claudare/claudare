# Proxy server

A simple, non-error handling server that proxies messages between peers. No
authentication is implemented. An actor can only connect once.
Connections require nonempty `Claudare-Actor` and `Claudare-Group` HTTP
headers.

# Running it

```sh
PORT=7000 dart run bin/main.dart
```

Run the Dart tester in another terminal from this directory. It connects two
actors and sends messages between them every three seconds until stopped.

```sh
PORT=7000 dart run bin/e2e.dart
```
