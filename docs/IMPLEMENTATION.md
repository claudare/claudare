# Core implementation guide

## Evidence boundary

This document is based on static inspection of the current workspace. It
describes executable source paths, not completed runtime verification.

## Core package layout

Core is the reusable, application-independent layer. It will span multiple
packages. Today, its CQRS portion is in `packages/cqrs`, its CRDT value helpers
are in `packages/crdt`, its shared causal and serialization primitives are in
`packages/common`, its ID generators are in `packages/id_generator`, its
time providers are in `packages/time_provider`, and `isolate_sqlite` and
`claudare_logging` provide core SQLite and logging boundaries.

See [CONVENTIONS.md](../CONVENTIONS.md) for the wiring conventions that govern
new or modified Core code.

## CQRS implementation

`packages/cqrs` exposes command inputs and handlers, stream contexts, event
codecs, a mutexed event store, memory and SQLite event databases, projection
runtime, runtime and projection-progress stores, and test utilities.
`packages/id_generator` exposes the ID
generator contract and secure, seeded, sequential, and static implementations.
`packages/common` exposes dots, integer-keyed version vectors, and JSON byte
conversion. CQRS owns `CommandId` and indexed `EventId`.
`packages/time_provider` exposes the time provider contract, system clock, and
deterministic static implementation. `packages/crdt` exposes the
timestamp-based CRDT helpers.

A command uses `CommandContext` to access typed streams, declare locks, append
events, request IDs, and read the current time. `CommandExecutor` serializes
successful event-producing commands through `CommandCodecSafe` and calls
`EventStore.saveChanges`. Command handling exceptions propagate unchanged and
are not serialized or stored. Applications may use the exported
`CommandException` convention for non-fatal command rejection, or any other
`Exception`. `CommandExecutor` supplies database-local device ID zero and
`EventStore` allocates the next origin command sequence, receiver-local
command/event sequences, and stream versions under a read/write mutex.

Replicated command metadata and replicated events have separate flat models and
staging calls. Pending events have no command foreign key, so event-first,
partial, mixed-command, and out-of-order delivery are accepted. Promotion is an
explicit atomic operation that remains pending until command metadata,
dependency, next-origin ordering, and the complete indexed event set are ready.
Applied commands are paged by receiver-local command sequence; applied events
are queried separately by `CommandId` for ordered transport export. SQLite
derives the causal frontier with `MAX(sequence)` grouped by device ID from
applied commands; memory derives the same value rather than caching it.

`CqrsRuntime` validates projection names, versions, and route definitions, then
creates projection runners and initializes or rebuilds them from stored
runtime-version and per-projection sequence state. A generic projection owns one
typed stream route and event handler. `Projection<Object, TParams>` supports
manual runtime-type checks without bypassing registry decoding.
`RuntimeStore` records applying and applied boundaries by globally
unique projection name. A boundary mismatch triggers reset and replay from
zero. Applications choose whether a projection is consistent, so command
completion waits for its callback, or eventual, so it is queued without
blocking the command.

Events are authoritative. Projections are disposable derived state and repair
themselves through reset and replay. Projection read-model changes and runtime
progress are intentionally non-atomic; the two-boundary protocol detects an
interruption. Reset implementations drop and recreate all schema they own.
The required projection batch callback is not yet invoked by the current
event-at-a-time runtime; page callback delivery is part of the planned pump
cutover.

## Current core limits

- SQLite migration markers use `db.execute` rather than the transaction
  context, so schema work and its marker are not atomic.
- Runtime lifecycle, projection queue draining, degraded state, and shutdown
  are not explicit public behavior.
- Integer device IDs are database-local and are not authenticated identity.
  Version vectors and pending storage do not provide transport, peer identity,
  replay authentication, or application convergence.

## Core support packages

`IsolateSqlite` owns one SQLite connection in a dedicated isolate. It receives
synchronous callbacks for `run` and `transaction`; transactions use `BEGIN`,
`COMMIT`, and `ROLLBACK`.

`claudare_logging` supplies the explicit `Logger` interface, `NoopLogger`, and
`RecordingLogger`. See [CONVENTIONS.md](../CONVENTIONS.md) for Core wiring and
error-handling conventions.

## Prototype evidence

`apps/notes` is the first consumer used to develop and exercise core. It
composes the CQRS runtime, SQLite event database/store pair, application-defined projections,
and query models. Its note domain, table layout, UI behavior, fixed startup
data, and search behavior are prototype details, not core contracts.

## Tests and validation

The repository has Dart tests for core commands, stores, projections, finance
examples, logging, and SQLite isolation. The notes smoke test does not exercise
product behavior. Run root analysis plus relevant member tests while iterating;
use `fvm dart run melos run test` for cross-workspace work.
