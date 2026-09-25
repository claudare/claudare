# Implementation Details

The packages under `packages/*` are application-independent. Notes consumes them
as a Flutter prototype and does not define their shared APIs.

## Package ownership

| Package            | Ownership                                                       |
| ------------------ | --------------------------------------------------------------- |
| `cqrs`             | Commands, event codecs and storage, aggregates, and the runtime |
| `common`           | Async, pagination, and serialization primitives                 |
| `crdt`             | Text CRDT, editor binding, and timestamp-based value helpers    |
| `id_generator`     | ID generation                                                   |
| `time_provider`    | System and deterministic clocks                                 |
| `isolate_sqlite`   | SQLite library                                                  |
| `claudare_logging` | Explicit logging contracts and implementations                  |
| `package_template` | Scaffold for another workspace package                          |

Shared packages do not depend on applications. Consumers use public package
entrypoints. Coding rules are in [CONVENTIONS.md](../CONVENTIONS.md).

## CQRS data model

`CqrsRuntime` executes commands and resolves aggregates. A command reads typed
event streams, validates a change, and appends events. `EventStore` persists an
accepted command and its events atomically. The event history is authoritative.

Each application registers codecs for its event types. An aggregate selects
events by route and rebuilds state for a query. The CQRS package supports
optional snapshots.

Events, not read models, are authoritative application state. Each concrete
event type has an application-owned `EventCodec` with a stable persisted kind.
Commands create events and append them to the event store. The events are
durable after successful command execution. Failed commands dont affect the
event store.

See [App Development Guide](APP_DEVELOPMENT_GUIDE.md) for application
composition and [Security](SECURITY.md) for the current security posture.
