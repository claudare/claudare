# Proxy server

A simple, non-error handling server that proxies messages between peers. No
authentication is implemented. An actor can only connect once.

# Running it

```
$ PORT=8080 dart run bin/server.dart
Proxy server listening on port 8080
```
