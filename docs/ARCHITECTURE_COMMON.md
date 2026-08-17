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

Each concrete event type has one application-owned `EventCodec` with an
explicit persisted kind. `CqrsRuntime` owns the internal registry that encodes
command events by Dart type and decodes command-stream reads, live delivery,
and replay by persisted kind.

`CqrsRuntime` validates and constructs projection runners. Each projection has
a globally unique name, a positive model version, one typed stream route, and
one typed event handler. The runtime store owns each projection's version plus
applying-through and scanned-through local event-sequence boundaries. Missing,
changed, or interrupted projections rebuild independently while unchanged
projections resume. The runtime separates consistent projection routing from
eventual routing. Events remain authoritative; read models are disposable
derived state.

## Event-store contract

`EventStore` owns locking, optimistic stream checks, causal-frontier
advancement, and receiver-local sequence allocation. It wraps a raw
`EventDatabase`; memory and SQLite databases accept resolved records and write
them atomically without generating identifiers.

Each replicated command has a CQRS-owned `CommandId`, a causal `dependency`,
encoded command data, timestamps, and a positive event count. Each replicated
event has an `EventId`, stream path, encoded event data, and occurrence time.
`CommandId` extends the common `Dot`; `EventId` adds its zero-based index within
the command.

Commands and events are transported and staged separately. Events may arrive
before command metadata, in arbitrary order, and mixed across command IDs.
Byte-identical retransmission is idempotent while changed content under an
existing ID is rejected. Explicit promotion waits for the command dependency,
the next origin sequence, and exactly the indexed events `0..eventCount - 1`.
Promotion assigns receiver-local event sequences and stream versions in event
index order, then writes one flat applied command and its flat events atomically.

`EventStore.getAppliedEventReader` exposes that complete applied-event history
in ascending receiver-local sequence pages. Its cursor is exclusive and zero
starts at the beginning. `appliedChanges` is an asynchronous broadcast signal
emitted after a successful non-empty local append or pending-command promotion.
It carries no records, and staging, unsuccessful promotion, empty commands, and
failed writes do not emit. Consumers recover details from the durable reader.
The current runtime does not subscribe to this signal yet.

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

A generic `Projection<TEvent, TParams>` owns one typed `StreamRoute`, applies
decoded events with parsed stream parameters, can reset its derived state, and
declares a required batch-completion callback. For manual runtime-type checks,
`Projection<Object, TParams>` receives the registry-decoded object and checks
its type inside `apply`.
`ProjectionRuntime` catches up after the sequence stored by `RuntimeStore` and
routes live committed events through the same advancement protocol. Startup
replay reads complete unfiltered event pages, applies only matching routes, and
advances scanned progress to each page end even when nothing matches. A missing
state, changed version, or disagreeing applying/scanned boundary triggers reset
and replay from sequence zero. Projection errors make the derived state
unhealthy; the event history remains available for repair by reset/replay.

The batch callback is part of the implemented projection contract. An isolated
internal event pump now advances page progress and invokes the callback once
after each matched page commits. It also exercises single-flight scans, page
barriers, and terminal failure behavior in white-box tests. The production
runtime does not own or invoke this pump yet: startup and the current live path
still use legacy projection delivery, and direct delivery still uses the
temporary append-order save result. Runtime signal consumption, production
callback delivery, public failure state, shutdown, and removal of direct
delivery belong to the Stage 7 cutover.

See [APP_PATTERNS.md](APP_PATTERNS.md) for the application event-codec pattern
and its file layout.

Runtime-store progress and application read-model writes are not one atomic
transaction. The runtime writes the applying boundary, awaits the projection,
then writes the scanned-through boundary. An interruption leaves a mismatch
that causes only that projection to rebuild on the next startup. Reset must
drop all projection-owned schema if present and recreate its complete current
schema. Projections must be safe to rebuild from event history and must not
treat read-model data as the source of truth.

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
