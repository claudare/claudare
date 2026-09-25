# Implementation Details

The packages under `packages/*` are application-independent. Notes consumes them
as a Flutter prototype and does not define their shared APIs.

## Package ownership

| Package            | Ownership                                                       |
| ------------------ | --------------------------------------------------------------- |
| `cqrs`             | Commands, event codecs and storage, aggregates, and the runtime |
| `common`           | Async, pagination, and serialization primitives                 |
| `crdt`             | Timestamp-based latest-write-wins helpers                       |
| `id_generator`     | ID generation                                                   |
| `time_provider`    | System and deterministic clocks                                 |
| `isolate_sqlite`   | SQLite isolation, migrations, and transactions                  |
| `claudare_logging` | Explicit logging contracts and implementations                  |
| `queue`            | FIFO coordination for asynchronous tasks                        |
| `package_template` | Scaffold for another workspace package                          |

Shared packages do not depend on applications. Consumers use public package
entrypoints. Coding rules are in [CONVENTIONS.md](../CONVENTIONS.md).

## CQRS model

`CqrsRuntime` executes commands and resolves aggregates. A command reads typed
event streams, validates a change, and appends events. `EventStore` persists an
accepted command and its events atomically. The event history is authoritative.

Each application registers codecs for its event types. An aggregate selects
events by route and rebuilds state for a query. The CQRS package supports
optional snapshots, while Notes replays its note events without snapshots. Notes
persists events in one SQLite database and keeps no derived database.

CQRS owns command identities and causal dependencies keyed by plain actor
strings. The event store can store and retrieve complete `StoredCommand` values.
This does not provide network transport, device enrollment, multi-device
convergence, encryption, blob storage, or backup.

See [App Development Guide](APP_DEVELOPMENT_GUIDE.md) for application
composition and [Security](SECURITY.md) for the current security posture.
