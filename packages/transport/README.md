# Transport

Peer transport contracts and multiplexing for independent protocols over one
connection.

Register each protocol with `channel(name)` or `sessions(name)` before sending
messages. Messages for unregistered names are discarded. Use `sessions(name)` to
receive the initial channel and its replacements when either peer resets that
protocol.
