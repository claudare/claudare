# Implementation Details

The packages under `packages/*` form Claudare's reusable,
application-independent foundation. They currently support local event-sourced
applications. The Notes application consumes these packages but does not define
their APIs or ownership.

## Package ownership

| Package            | Ownership                                                                                         |
| ------------------ | ------------------------------------------------------------------------------------------------- |
| `cqrs`             | Commands, event codecs and storage, projections, runtime progress, and `CqrsRuntime` coordination |
| `common`           | Async coordination, causal dots and version vectors, paginated readers, and JSON byte conversion  |
| `crdt`             | Timestamp-based latest-write-wins value helpers                                                   |
| `id_generator`     | 128-bit ID generator contract plus secure and deterministic implementations                       |
| `time_provider`    | Clock contract plus system and deterministic implementations                                      |
| `isolate_sqlite`   | A SQLite connection owned by a dedicated isolate, migrations, and transaction helpers             |
| `claudare_logging` | Explicit logger contract and console, no-op, and recording implementations                        |
| `queue`            | FIFO coordination for asynchronous tasks                                                          |
| `package_template` | Non-runtime scaffold for creating another workspace package                                       |

Shared packages do not depend on applications. Consumers use a package's public
library entrypoint rather than importing its `src` directory. Coding boundaries
for new work are in [CONVENTIONS.md](../CONVENTIONS.md).

## CQRS model

```text
command
  -> stream replay and append
  -> EventStore
  -> authoritative event history
  -> projection replay and live catch-up
  -> disposable read model
```

A `Command` receives typed input and a `CommandContext`. The context provides
typed stream access, IDs, time, and the runtime logger. Reading a stream records
the version the command observed. When events are saved, `EventStore` compares
those versions with current storage and rejects stale concurrent work. Accepted
commands and events are persisted atomically by the selected `EventDatabase`.

Events, not read models, are authoritative application state. Each concrete
event type has an application-owned `EventCodec` with a stable persisted kind.
The application's `EventRegistry` encodes events by Dart type and decodes stored
events by kind. Registry contents are frozen when the runtime initializes, so
all codecs and projections must be registered during composition.

`CqrsRuntime` coordinates command execution, `EventStore`, projection replay,
and runtime progress. Command completion means the accepted event batch is
durable. Projection updates are a later asynchronous step unless a caller
explicitly awaits the runtime pump. Durable history allows a projection to catch
up after startup or interruption.

## Projections and runtime progress

A `Projection<TEvent, TParams>` selects streams with a typed route, applies
decoded events to one application-owned read model, defines reset behavior, and
notifies the application after matched batches. The runtime records progress by
globally unique projection name and model version.

Missing progress, a version change, or evidence of an interrupted apply causes
only the affected projection to reset and replay from the beginning. Other
projections resume from their recorded positions. Every projection must
therefore be able to delete and recreate all derived state it owns. Progress
also advances across durable history that does not match a projection, so live
catch-up does not repeatedly rescan unrelated events.

Read-model writes and runtime progress are not one transaction. This is why read
models are disposable and why reset/replay is part of the projection contract.
`onBatchApplied` lets applications notify controllers after visible read-model
work without making UI notification part of event persistence.

## Replicated-command storage primitives

`EventStore` implements storage-level staging for replicated command metadata
and replicated events. The two may arrive separately and in any order.
Byte-identical retransmission is accepted as already present, while different
content under an existing command or event ID is rejected.

Promotion is explicit. A pending command becomes visible in applied history only
when its causal dependency, next sequence for its origin, and complete indexed
event set are available. Promotion then assigns receiver-local ordering and
stream versions and persists the command and events atomically. Promoted events
enter the same durable projection path as locally executed events.

These primitives are not a replication system. The repository has no network
transport, stable device identity, device enrollment or membership, promotion
scheduler, application convergence guarantee, authenticated wire format,
encryption, blob transfer, or backup. Integer device IDs and version vectors are
database-local causal data, not authenticated identities or security controls.
Applications must eventually define deterministic conflict semantics before
multi-device behavior can be claimed.

## Supporting primitives

`common` provides the causal and utility types used across packages. `Dot` and
integer-keyed version vectors represent database-local sequence knowledge.
`PaginatedReader` turns cursor-based page functions into incremental scans. JSON
conversion supplies a simple byte boundary. `AsyncTrailingRunner` serializes
asynchronous work and coalesces overlapping requests into a final trailing run,
which is useful for read-model refreshes.

`crdt` currently exports only a timestamp-based latest-write-wins value and its
value/timestamp pair. An equal or later incoming timestamp wins. There is no
actor tie-breaker, text CRDT, causal delivery mechanism, conflict UI, or
convergence proof, so the helper is not a complete replicated-data system.

`id_generator` separates ID allocation from domain code and provides secure,
seeded, sequential, and static implementations. `time_provider` similarly
separates current time from domain behavior and provides system and
deterministic clocks. These abstractions support production composition and
reproducible tests through constructor injection.

`IsolateSqlite` owns one SQLite connection in a dedicated isolate. Callers send
synchronous database callbacks through its run and transaction boundaries, and
applications remain responsible for connection ownership and closure.

`claudare_logging` supplies the explicit logging dependency used by the runtime
and applications. `queue` provides FIFO execution for asynchronous tasks.

See [App Development Guide](APP_DEVELOPMENT_GUIDE.md) for application
composition and [Security](SECURITY.md) for the current security boundary.
