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
codecs, a mutexed event store, memory and SQLite event databases, the CQRS
runtime and event pump, projection-progress stores, and test utilities.
`packages/id_generator` exposes the ID
generator contract and secure, seeded, sequential, and static implementations.
`packages/common` exposes dots, integer-keyed version vectors, and JSON byte
conversion. CQRS owns `CommandId` and indexed `EventId`.
`packages/time_provider` exposes the time provider contract, system clock, and
deterministic static implementation. `packages/crdt` exposes the
timestamp-based CRDT helpers.

A command uses `CommandContext` to access typed streams, declare locks, append
events, request IDs, read the current time, and use the runtime's `Logger`.
`CommandExecutor` serializes
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

The unfiltered `EventStore.getAppliedEventReader` pages every applied event in
ascending receiver-local sequence order after an exclusive cursor.
`EventStore.appliedChanges` asynchronously broadcasts once after a successful
non-empty local append or pending-command promotion. It does not emit for
empty, failed, rejected, staged, missing, or not-ready changes. The signal
carries no records. `CqrsRuntime` uses it only to request another durable scan.
`EventStore.saveChanges` returns after the command batch is durable and exposes
no append-order reconstruction.

`EventPump` starts each requested scan after the minimum prepared projection
position, decodes each durable event once, processes projection adapters
concurrently behind a per-page barrier, and advances every participating
projection through the page end. Matching events remain sequential within a
projection, and its batch callback runs once after committed page progress.
Concurrent requests coalesce while forcing another scan, so events added during
processing or an empty read are not stranded. The pump waits for every
projection task started for a page and reports the first page failure before
reading another page.

`CqrsRuntime.initialize` freezes registration, migrates the event store,
initializes runtime storage, selectively prepares projections, subscribes to
applied changes, and awaits startup pumping. It exposes explicit pumping,
serialized rebuild-all maintenance, a stored terminal pump failure, a broadcast
failure stream, and idempotent close. Internal lifecycle state rejects misuse
with synchronous `StateError`. Only failures reached through `EventPump.pump()`
become `CqrsRuntimeFailure`; command, persistence, and non-pump initialization
or rebuild failures propagate unchanged. Initialization failures automatically
close the runtime, while non-pump command and rebuild failures leave a running
runtime available.
The runtime constructs exactly one `EventStore` from its injected
`EventDatabase`. Closing the runtime cancels its EventStore subscription and
closes the store. `EventStore.close()` closes its notification stream and its
database; other application-owned databases remain the application's
responsibility.

The runtime initializes or rebuilds projections from stored per-projection
version and page state. A generic projection owns one
typed stream route and event handler. `Projection<Object, TParams>` supports
manual runtime-type checks without bypassing registry decoding.
`RuntimeStore` records the projection version plus applying-through and
scanned-through local sequence boundaries by globally unique projection name.
A missing state, version mismatch, or boundary mismatch resets only that
projection before replay from zero. Matching projections resume after their
scanned-through boundary. Commands complete after durable persistence and never
wait for projection progress. Tests may await `pump` for deterministic read
models.

Events are authoritative. Projections are disposable derived state and repair
themselves through reset and replay. Projection read-model changes and runtime
progress are intentionally non-atomic; the two-boundary protocol detects an
interruption. Reset implementations drop and recreate all schema they own.
Startup replay reads unfiltered event pages and advances each projection to the
page end, including pages with no matching routes. It writes runtime progress
once before and once after each page while keeping matching read-model writes
sequential. Projection `onBatchApplied` callbacks let applications notify
listenable read models after a matched page commits.

## Current core limits

- SQLite migration markers use `db.execute` rather than the transaction
  context, so schema work and its marker are not atomic.
- The runtime-store SQLite schema is a clean development replacement and does
  not migrate existing global-version or old projection-progress tables.
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

The repository has Dart tests for core commands, stores, projections, runtime
lifecycle and failures, finance examples, logging, and SQLite isolation. Notes
tests cover projection rebuilds, read-model notifications, and reload
coalescing. Run root analysis plus relevant member tests while iterating; use
`fvm dart run melos run test` for cross-workspace work.
