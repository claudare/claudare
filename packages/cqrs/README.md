# cqrs

Build applications that record commands and events and derive state from that
history. Supply domain commands, event codecs, and aggregates to the runtime.

Use memory storage for tests and temporary data, or SQLite for persistence. Open
and migrate SQLite stores before use; closing a store also closes its supplied
database.

Commands can write blobs alongside events. Supply `const NoBlobStore()` when
your application does not use blobs.

For peer transport and replication, see [sync](../sync/README.md). Actor
identifiers do not provide authentication.
