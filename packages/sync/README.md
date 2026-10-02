# Sync

Owns the shared proxy protocol types `ProxyMessage`, `ProxyMessageType`, and
`ProxyInit`, exported by `package:sync/sync.dart`.

Proxy messages carry direct or broadcast payloads. Connection initialization
uses actor and group HTTP headers. These types do not provide authentication
or encryption. The proxy server and its development e2e tester live in
`backend/proxy`.
