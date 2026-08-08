# Core architecture

## Purpose and ownership

Core is the reusable, application-independent foundation of Claudare. It will
span multiple packages as the system grows. Today, `packages/core` contains the
CQRS runtime and foundational domain helpers, `packages/isolate_sqlite` owns
the SQLite isolation boundary, and `packages/claudare_logging` provides the
logging abstraction.

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
      -> durable command/event records
  -> ProjectionRuntime replay and live routing
      -> application-owned read models
```

`CommandContext` supplies typed stream access, nacking, new IDs, and current
time. A command locks a stream by reading it and records expected stream
versions. `CommandExecutor` serializes the command, captures a success/nack/
exception result, and sends the command plus all stream appends to the event
store.

`CqrsRuntime` constructs projection runners and uses a stored runtime version
to decide when projections must reset and replay. It separates consistent
projection routing from eventual routing. Events remain authoritative; read
models are disposable derived state.

## Event-store contract

The common `EventStore` combines command, projection-read, and administration
operations. Its implementations are memory-backed and SQLite-backed. The SQLite
implementation stores stream heads, encoded events, command records, and
local/device/causal sequence values in one database transaction for a command
write.

Local sequence is the ordering used for a store's projection replay. Stream
version is the optimistic-concurrency boundary for one stream. Device and
causal sequence values are local primitives only; without stable authenticated
identity, import/export, deduplication, and deterministic conflict rules, they
are not a distributed protocol.

The in-memory and SQLite stores currently implement the same `EventStore`
contract. See [CONVENTIONS.md](../CONVENTIONS.md) for the implementation and
parity-testing conventions that govern changes to that contract.

## Projection contract

A `Projection` names its event codec and stream-ID pattern, owns a checkpoint,
can reset its derived state, and applies decoded events with metadata.
`ProjectionRuntime` catches up by querying events after the checkpoint and
routes live committed events through a FIFO queue. Projection errors make the
derived state unhealthy; the event history remains available for repair by
reset/replay.

See [APP_PATTERNS.md](APP_PATTERNS.md) for the application event-codec pattern
and its file layout.

Projection implementations own the atomicity of their read-model write and
checkpoint update. They must be safe to rebuild from event history and must not
treat read-model data as the source of truth.

## CRDT helpers

`core/crdt.dart` currently exports only a timestamp-based latest-write-wins
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
Before extending it to multiple devices, specify stable event identity,
authenticated membership, canonical import/export, idempotent deduplication,
causal buffering, deterministic domain merges, resource limits, and a reviewed
cryptographic design. See [IMPROVEMENTS.md](IMPROVEMENTS.md) for the required
order of work.
