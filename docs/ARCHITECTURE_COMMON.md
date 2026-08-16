# Core architecture

## Purpose and ownership

Core is the reusable, application-independent foundation of Claudare. It will
span multiple packages as the system grows. Today, `packages/cqrs` contains the
CQRS runtime, `packages/common` owns shared causal and serialization primitives,
`packages/id_generator` owns ID generation, `packages/time_provider`
owns time providers, `packages/crdt` contains CRDT value helpers,
`packages/isolate_sqlite` owns the SQLite isolation boundary, and
`packages/claudare_logging` provides the logging abstraction.

The current core supports local event-sourced applications. It does not provide
replication, network transport, cryptography, device membership, blob storage,
or backup.

## CQRS flow

```text
Command input
  -> Command.handle(context)
      -> CommandStream reads and optimistic locks
      -> appended encoded events
  -> EventStore.saveChanges
      -> EventDatabase atomic command/event records
  -> ProjectionRuntime replay and live routing
      -> application-owned read models
```

`CommandContext` supplies typed stream access, new IDs, and current time. A
command locks a stream by reading it and records expected stream versions.
`CommandExecutor` sends successful event-producing commands to the event store.
Application exceptions propagate unchanged and are not persisted. Successful
commands without events are discarded.

`CqrsRuntime` constructs projection runners. The runtime store owns each
globally named projection's applying and applied event-sequence boundaries,
while a stored runtime version triggers whole-runtime rebuilds. It separates
consistent projection routing from eventual routing. Events remain
authoritative; read models are disposable derived state.

## Event-store contract

`EventStore` owns locking, optimistic stream checks, causal-frontier
advancement, and receiver-local sequence allocation. It wraps a raw
`EventDatabase`; memory and SQLite databases accept resolved records and write
them atomically without generating identifiers.

Each replicated command has a CQRS-owned `CommandId`, a causal `dependency`,
encoded command data, timestamps, and a positive event count. Each replicated
event has an `EventId`, stream ID, encoded event data, and occurrence time.
`CommandId` extends the common `Dot`; `EventId` adds its zero-based index within
the command.

Commands and events are transported and staged separately. Events may arrive
before command metadata, in arbitrary order, and mixed across command IDs.
Byte-identical retransmission is idempotent while changed content under an
existing ID is rejected. Explicit promotion waits for the command dependency,
the next origin sequence, and exactly the indexed events `0..eventCount - 1`.
Promotion assigns receiver-local event sequences and stream versions in event
index order, then writes one flat applied command and its flat events atomically.

Event `local_sequence` orders projection replay. Receiver-local command
sequence orders export and diagnostics. `stream_version` is only a local
optimistic-concurrency boundary. Applied events retain device ID, command
sequence, and event index for transport export. Local command execution uses
database-local device ID zero. Peer communication must translate stable peer
identity into unrestricted integer device IDs before records reach CQRS.
Transport and promotion scheduling remain outside CQRS.

CQRS does not merge, reject, or globally order causally concurrent commands.
Applications own out-of-date event semantics, and the core makes no replicated
convergence claim. The in-memory and SQLite databases share one behavioral
contract.

## Projection contract

A `Projection` names its event codec and stream-ID pattern, can reset its
derived state, and applies decoded events with occurrence-time metadata.
`ProjectionRuntime` catches up after the sequence stored by `RuntimeStore` and
routes live committed events through the same advancement path. Missing or
disagreeing applying/applied boundaries trigger reset and replay from sequence
zero. Projection errors make the derived state unhealthy; the event history
remains available for repair by reset/replay.

See [APP_PATTERNS.md](APP_PATTERNS.md) for the application event-codec pattern
and its file layout.

Runtime-store progress and application read-model writes are not one atomic
transaction. The runtime writes the applying boundary, awaits the projection,
then writes the applied boundary. An interruption leaves a mismatch that causes
a rebuild on the next startup. Reset must drop all projection-owned schema if
present and recreate its complete current schema. Projections must be safe to
rebuild from event history and must not treat read-model data as the source of
truth.

## CRDT helpers

`crdt/crdt.dart` exports only a timestamp-based latest-write-wins
value and its value/timestamp pair. Merging keeps an incoming value when its
timestamp is equal to or later than the current timestamp.

This helper is not a complete replicated-data system: equal timestamps have no
stable actor/event tie-breaker, timestamps are not authenticated logical clocks,
and it supplies no text CRDT, causal delivery, conflict UI, or convergence
proof. Use it only where the application accepts those local semantics. Any
multi-device domain needs an explicit deterministic conflict model plus
permutation tests.

## SQLite and logging boundaries

`IsolateSqlite` owns one SQLite connection in a dedicated isolate. Callers pass
synchronous callbacks to `run` or `transaction`; the latter surrounds a
callback with `BEGIN`/`COMMIT`/`ROLLBACK`.

`Logger` is an explicit dependency of `CqrsRuntime`. `NoopLogger` and
`RecordingLogger` provide suppressed and inspectable output. Core wiring and
error-handling conventions are defined in
[CONVENTIONS.md](../CONVENTIONS.md).

## Limits of the current core

Core is suitable for local CQRS experiments, not security or sync claims.
Before enabling transport, specify authenticated membership, canonical wire
encoding, pending scheduling and bounds, application convergence rules,
resource limits, and a reviewed cryptographic design. See
[IMPROVEMENTS.md](IMPROVEMENTS.md) for the required order of work.
