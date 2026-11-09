# Implementation Details

The packages under `packages/*` are application-independent. The Dart Notes core
in `apps/notes` consumes them, and the Flutter prototype in `frontends/notes`
consumes that core. Neither defines shared package APIs.

## Package ownership

Important workspace packages are listed below.

| Package            | Ownership                                                    |
| ------------------ | ------------------------------------------------------------ |
| `cqrs`             | Commands, event codecs and storage, aggregates, and runtime  |
| `blob`             | Blob storage, CQRS integration, and blob replication         |
| `crdt`             | Text CRDT, editor binding, and timestamp-based value helpers |
| `sync`             | Actor identities and replication coordination                |
| `transport`        | Peer discovery, channels, and protocol multiplexing          |
| `id_generator`     | ID generation                                                |
| `time_provider`    | System and deterministic clocks                              |
| `claudare_logging` | Explicit logging contracts and implementations               |
| `isolate_sqlite`   | SQLite library                                               |

Shared packages do not depend on applications. Consumers use public package
entrypoints. Coding rules are in [CONVENTIONS.md](../CONVENTIONS.md).

See [App Development Guide](APP_DEVELOPMENT_GUIDE.md) for application
composition and [Security](SECURITY.md) for the current security posture.

## CQRS data model

Claudare applications use CQRS and event sourcing for data modeling and
replication.

### Event sourcing

`CqrsRuntime` executes commands and resolves read models from events. A command
reads typed event streams, validates a change, and appends events. `EventStore`
persists an accepted command and its events atomically. Failed commands do not
commit events.

Events, not read models, are authoritative application state. Each concrete
event type has an application-owned `EventCodec` with a stable persisted kind.

Aggregates and projections are read models used to query application data.

An aggregate selects events by path filter and synchronously applies them to its
state. It can resume from its last applied log position. Snapshot persistence is
not provided.

A projection applies matching events asynchronously, replaying existing events
and following new ones. It can resume from persisted state and a log position;
the projection implements its own persistence.

### Large file storage

Large files (blobs) are stored in the `BlobStore`. Commands can save and delete
blobs by injecting `BlobWriter` into the concrete `Command`. Blobs can be read
using the `BlobReader` interface. Blob bytes are stored separately from events.
However, their metadata is saved to the event-store within the same command.

### Replication

The `sync` package coordinates cross-device replication over `Transport`.
Stored commands and their events are replicated together; optional blob
replication transfers bytes separately. Replication has not been finalized yet.
