# cqrs

Build applications that record commands and events and derive state from that
history. Supply domain commands, event codecs, and aggregates to the runtime.

Use memory storage for tests and temporary data, or SQLite for persistence. Open
and migrate SQLite stores before use; closing a store also closes its supplied
database.

For peer transport and replication, see [sync](../sync/README.md). Actor
identifiers do not provide authentication.
