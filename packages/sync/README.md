# Sync

Owns peer transport and replication primitives, including the shared proxy
protocol types `ProxyMessage`, `ProxyMessageType`, and `ProxyInit`. Public types
are exported by `package:sync/sync.dart`.

Proxy messages carry direct or broadcast payloads. Connection initialization
uses actor and group HTTP headers. These types do not provide authentication
or encryption. The proxy server and its development e2e tester live in
`backend/proxy`.

`WebSocketProxyTransport` discovers peers through one proxy connection and
provides ordered String channels. It uses session keepalives to detect inactive
peers and can discover replacement sessions. Socket closure ends the transport;
the caller must create another instance to reconnect.

Construct the transport with its URL, actor, group, logger, ID generator, and
time provider. Subscribe to `peerTransports` before calling `start()`. Each peer
channel belongs to one session. Closing it ends that session. Actors must be
unique among connected clients, and session IDs must be fresh across reconnects.
Discovery and keepalive intervals default to 5 seconds, and inactivity timeouts
to 15 seconds; all are configurable. Unanswered handshakes expire, allowing
discovery to establish a fresh session.

`ReplicationMessageCodec` converts between replication messages and String JSON.
Use `StreamChannelTransformer.fromCodec` to apply it to a peer channel, and
create a new `Replicator` for each replacement channel. These are development
primitives, not a complete synchronization system. Transport delivery is
live-only, and detection of a lost peer is delayed until timeout.
