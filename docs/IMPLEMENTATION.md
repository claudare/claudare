# Core implementation guide

## Evidence boundary

This document is based on static inspection of the current workspace. It
describes executable source paths, not completed runtime verification.

## Core package layout

Core is the reusable, application-independent layer. It will span multiple
packages. Today, its CQRS portion is in `packages/cqrs`, its CRDT value helpers
are in `packages/crdt`, its shared device, sequence, and serialization primitives
are in `packages/common`, its ID generators are in `packages/id_generator`, its
time providers are in `packages/time_provider`, and `isolate_sqlite` and
`claudare_logging` provide core SQLite and logging boundaries.

See [CONVENTIONS.md](../CONVENTIONS.md) for the wiring conventions that govern
new or modified Core code.

## CQRS implementation

`packages/cqrs` exposes command inputs and handlers, stream contexts, event
codecs, memory and SQLite event stores, projection runtime, runtime-version
repositories, and test utilities. `packages/id_generator` exposes the ID
generator contract and secure, seeded, sequential, and static implementations.
`packages/common` exposes device IDs, device/causal sequence helpers, and JSON
byte conversion.
`packages/time_provider` exposes the time provider contract, system clock, and
deterministic static implementation. `packages/crdt` exposes the
timestamp-based CRDT helpers.

A command uses `CommandContext` to access typed streams, declare locks, append
events, nack invalid input, request IDs, and read the current time.
`CommandExecutor` serializes the command, records its result, and calls
`EventStore.saveChanges`. The SQLite implementation persists command records,
stream heads, encoded events, and sequences in one transaction.

`CqrsRuntime` creates projection runners, initializes or rebuilds them from
stored runtime version state, and routes committed events. Applications choose
whether a projection is consistent, so command completion waits for its
callback, or eventual, so it is queued without blocking the command.

Events are authoritative. Projections are disposable derived state and repair
themselves through reset and replay.

## Current core limits

- SQLite migration markers use `db.execute` rather than the transaction
  context, so schema work and its marker are not atomic.
- Runtime lifecycle, projection queue draining, degraded state, and shutdown
  are not explicit public behavior.
- Device and causal sequences are local values, not authenticated identity,
  replication order, or replay protection.

## Core support packages

`IsolateSqlite` owns one SQLite connection in a dedicated isolate. It receives
synchronous callbacks for `run` and `transaction`; transactions use `BEGIN`,
`COMMIT`, and `ROLLBACK`.

`claudare_logging` supplies the explicit `Logger` interface, `NoopLogger`, and
`RecordingLogger`. See [CONVENTIONS.md](../CONVENTIONS.md) for Core wiring and
error-handling conventions.

## Prototype evidence

`apps/notes` is the first consumer used to develop and exercise core. It
composes the CQRS runtime, SQLite event store, application-defined projections,
and query models. Its note domain, table layout, UI behavior, fixed startup
data, and search behavior are prototype details, not core contracts.

## Tests and validation

The repository has Dart tests for core commands, stores, projections, finance
examples, logging, and SQLite isolation. The notes smoke test does not exercise
product behavior. Run root analysis plus relevant member tests while iterating;
use `fvm dart run melos run test` for cross-workspace work.
