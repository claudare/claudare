# CQRS runtime rework plan

Status: Stages 0-8 are implemented. Stages 9-10 remain future work. Stage 9
adds only deterministic test synchronization, and Stage 10 separately designs
production synchronization. Nothing in those remaining stages should be
treated as implemented behavior until the source and repository documentation
say so.

This is a clean development migration. The implementation does not need
backwards-compatible APIs, aliases, adapters, or parallel old and new runtime
paths. Replaced code and concepts should be removed completely during the
cutover.

## Motivation

Before Stage 7, the live event path was centered on `BoundCommand`. Events
produced by a command were persisted and then passed directly to selected
projection queues, while startup replay and replicated-command promotion used
different paths.

The reworked runtime will use the applied event history as the single source of
truth. Every event, including an event just produced by a local command, is
serialized and committed before projections see it. A single paginated pump
then reads, decodes, routes, and applies committed events in receiver-local
sequence order.

The extra encode/decode work is accepted for the first implementation. A fast
path may be considered later, after the durable path is correct and measured.

## Goals

- One application-owned `CqrsRuntime` coordinates command execution,
  projection registration, projection replay, and live projection progress.
- `EventStore` remains the authoritative event source.
- Local command events and promoted replicated events reach projections through
  the same pump.
- The application assembles one event registry and passes it to the runtime.
- A projection defines one typed event family and one `StreamRoute`.
- Projection version and replay progress are tracked per projection.
- Projection startup uses `scannedThroughLocalSequence` rather than the last
  matching event.
- Only one event page is pumped at a time, providing bounded backpressure.
- EventStore notifications request pumping but never carry event data.
- Projection callbacks notify application-owned listenable read models once per
  successfully applied page.
- Any unhandled runtime or projection failure puts the runtime into a terminal
  failed state so the application can show an error screen.
- The new design can later support replication without making the sync engine
  part of `CqrsRuntime`.

## Non-goals

- Preserving current runtime or projection APIs.
- Maintaining a compatibility layer during the rewrite.
- Avoiding the serialization round trip for locally produced events.
- Defining peer discovery, transport, device enrollment, encryption, or a full
  replication protocol.
- Claiming convergence for causally concurrent application commands.

## Core invariants

1. Projections consume only events that have been committed to `EventStore`.
2. `localSequence` is receiver-local and strictly orders local projection
   replay. It is not portable event identity or cross-device ordering.
3. A projection applies events in a strictly increasing `localSequence` order.
4. A projection's progress advances through every scanned page, including pages
   that contain no matching events for that projection.
5. At most one pump invocation reads and dispatches pages at a time.
6. The next page is not read until the current page has reached a terminal
   result for every participating projection.
7. Registration is frozen before initialization starts.
8. Event kinds, event types, projection names, and projection route definitions
   are validated before replay begins.
9. A lost wake-up cannot lose an event because the durable cursor is always the
   source of truth.
10. Projection state is disposable. Event history remains authoritative.
11. A failed runtime never resumes or repairs itself.

## Runtime ownership and lifecycle

The production application should construct and own exactly one `CqrsRuntime`.
This is an application wiring invariant, not a static singleton enforced by the
CQRS package. Tests may construct isolated runtimes with their own dependencies.

The runtime has an explicit lifecycle:

```text
configuring -> initializing -> running -> failed
                                  |
                                  v
                             closing -> closed
```

Before constructing the runtime, the application adds event codecs to an
`EventRegistry`, adds projections to a `ProjectionRegistry`, and passes both
registries to the runtime. During `initializing`, the runtime freezes
configuration, initializes stores, validates the registry, prepares projections,
and catches them up.
Commands cannot run until initialization succeeds.

`initialize()` freezes event and projection registration synchronously before
returning its future. Initialization is single-flight: concurrent callers receive
the same in-progress future and initialization work runs once. After successful
initialization the runtime accepts ordinary commands concurrently. EventStore
locking and optimistic stream checks remain responsible for protecting durable
state; the runtime does not serialize all command handlers.

Pumping is also single-flight. Projection rebuilds serialize with pumping. A
pump signal received during a rebuild does not run projection work concurrently;
it records a trailing scan that runs after the rebuild finishes. Stage 9 extends
runtime admission with a writer-preferred synchronization gate: ordinary
commands share admission, while an exclusive test-sync operation prevents new
commands and waits for admitted handlers before reading or importing records.

A failed runtime is terminal. It stops pumping, rejects later commands, and is
never automatically repaired, restarted, or reconstructed. The application may
show an error screen or banner. `close()` cancels subscriptions and releases
runtime-owned resources; it is also useful for tests. The runtime constructs and
owns exactly one `EventStore` from its injected `EventDatabase`. Runtime closure
closes that store, which also closes its database.

## Stream routing terminology

Stream routing uses web-style path and parameter terminology:

```dart
abstract class StreamRoute<TParams> {
  const StreamRoute();

  String get pattern;
  PatternFilter get filter;

  String buildPath(TParams streamParams);
  TParams parseParams(String streamPath);
  bool matches(String streamPath);
}
```

`StreamIdPattern` becomes `StreamRoute`. Its concrete implementations become
`StreamRouteAll` and `StreamRouteWildcard`. The persisted string is always named
`streamPath`; its typed application data is named `streamParams`.

This is a full clean rename. Dart fields, methods, locks, event records,
filenames, tests, application constants, and SQLite columns such as `stream_id`
become path-oriented. Existing development databases do not need a compatibility
migration.

The durable pump has only a persisted path, so the old route-to-route `globs`
fast path is removed. Routing uses `matches(streamPath)`, followed by
`parseParams(streamPath)` for matching projections.

## Event codecs and registry

Each persisted event kind has one codec:

```dart
abstract interface class EventCodec<T extends Object> {
  String get kind;

  Uint8List toBytes(T event);
  T fromBytes(Uint8List bytes);
}
```

The application assembles the registry before constructing the runtime:

```dart
final eventRegistry =
    EventRegistry()
      ..add(AccountOpenedCodec())
      ..add(AccountRenamedCodec());
final projectionRegistry =
    ProjectionRegistry()
      ..add(accountProjection);

final runtime = CqrsRuntime(
  dependencies: dependencies,
  eventRegistry: eventRegistry,
  projectionRegistry: projectionRegistry,
  runtimeName: 'accounts',
);
```

The registry maps:

- Stable persisted kind to a decoder.
- Dart event type to an encoder.

Registration must reject empty kinds, duplicate kinds, and duplicate Dart event
types. Persisted kinds are explicit protocol identifiers and must not be derived
from `runtimeType.toString()`.

Codec exception translation remains centralized at the codec boundary. Unknown
kinds and decoded values with an unexpected type are explicit runtime or
projection failures. They must not be silently skipped.

Event and command encoding failures propagate from command execution without
failing the runtime because no invalid event was committed. A durable event that
cannot be decoded fails the pump and is therefore a terminal runtime failure.

`CommandContext` and `CommandStream` use the registry supplied by the runtime.
Commands no longer carry an event-family codec when opening a stream. Appending
an event encodes it immediately into an `EventAppend`. The runtime does not keep
the original event object for direct projection delivery.

## Projection model

A projection owns one read model, one name, one version, one stream route, one
event handler, one reset operation, and a page-completion callback:

```dart
abstract interface class Projection<TEvent extends Object, TParams> {
  String get name;
  int get version;
  StreamRoute<TParams> get streamRoute;

  Future<void> reset();
  Future<void> apply(
    TParams streamParams,
    TEvent event,
    EventMetadata metadata,
  );
  void onBatchApplied();
}
```

The projection-level generic types keep the application handler typed. A sealed
event family supports an exhaustive switch in `apply`:

```dart
final class AccountProjection
    implements Projection<AccountEvent, AccountParams> {
  @override
  StreamRoute<AccountParams> get streamRoute => accountStreamRoute;

  @override
  Future<void> apply(
    AccountParams streamParams,
    AccountEvent event,
    EventMetadata metadata,
  ) async {
    // Apply the event to the read model.
  }
}
```

When the rare projection must handle unrelated event types, it implements
`Projection<Object, TParams>` and checks the registry-decoded object's runtime
type inside `apply`. A separate route primitive and multiple routes per
projection are unnecessary.

The application-owned `ProjectionRegistry` validates each projection when it is
added and rejects duplicate projection names. During Stage 7 initialization,
the runtime will prepare durable page adapters from the registered projections:

```dart
final projections = await projectionRegistry.prepare(
  runtimeStore,
  forceReset: false,
);
```

Preparation retains only consistent positions whose stored version matches the
projection version. New, inconsistent, version-changed, and explicitly
force-reset projections reset and start at sequence zero. The runtime store must
already be initialized before preparation.

`onBatchApplied()` is required, but projections that do not notify an
application listener may leave it empty. The pump calls it once after the
projection has successfully processed a page containing at least one matching
event and stored its scanned-through boundary. It is not called for a page with
no matching events. CQRS does not depend on Flutter `Listenable`; an application
projection may call an application-owned notifier from this method.

## Projection version and progress

Each projection declares its own positive model version. It is independent of
the application version. `RuntimeStore` persists at least:

```text
projection name
projection version
applying through local sequence
scanned through local sequence
```

`scannedThroughLocalSequence` means that the projection has considered every
event through that receiver-local sequence. It advances to the end of a page
even when no event in that page matches the projection.

During initialization:

- A new projection resets and starts at sequence zero.
- A projection whose stored version differs from its registered version resets
  and starts at sequence zero.
- A projection with mismatched applying/scanned boundaries is inconsistent and
  resets before replay.
- An unchanged, consistent projection resumes after its stored
  `scannedThroughLocalSequence`.
- Debug tooling may explicitly force all projections to rebuild.
- Non-debug startup rebuilds only projections that require it.

The runtime does not initially persist a separate global
`lastAppliedLocalSequence`. The safe all-projection watermark can be derived as
the minimum `scannedThroughLocalSequence` of the registered projections.
Per-projection progress is still required for new projections, selective
rebuilds, and interrupted-page recovery.

## The event pump

All projection delivery goes through one pump:

```text
local command commit -----+
                          |
replicated promotion -----+-> EventStore -> pump -> projections
                          |
startup ------------------+
```

The pump reads the unfiltered applied-event history in ascending receiver-local
sequence pages. Only one page is in flight. For each page it:

1. Determines which projections still need some or all of the page.
2. Decodes every needed event once through the central registry.
3. Matches `streamPath` against each projection's `StreamRoute`.
4. Builds the ordered event calls for each projection.
5. Marks each projection as applying through the page end.
6. Runs that projection's matching event calls sequentially.
7. Marks the projection as scanned through the page end, including when it had
   no matching event calls.
8. Calls `onBatchApplied()` if the projection had matching events.
9. Waits for every projection task before reading another page.

Projections process the page concurrently. Calls within one projection remain
sequential in increasing `localSequence`. Successful projections may store
progress and notify
before another projection fails. The pump still waits for every projection task
started for the page to settle before handling the result.

RuntimeStore writes projection progress only at the start and end of a page.
Projection handlers may perform whatever per-event read-model writes they need.
If five events match, the projection may write five times while RuntimeStore
writes only the applying and scanned-through boundaries. This is the intended
page recovery unit, not a deferred storage-transaction requirement.

This keeps memory bounded to approximately one event page and its projection
calls.
The design does not need an unbounded per-projection live-event queue.

When projections have different positions, the source reader starts after the
minimum consistent position. A projection ignores page events at or before its
own position and never moves backwards.

### Single-flight behavior

`pump()` is public, idempotent, and single-flight. If pumping is already active,
another call joins or marks the active pump to scan again before completing. A
typical coalescing model is:

```text
request arrives -> mark pump requested
active pump      -> drain pages until empty
new request      -> scan again before completing
no request       -> complete active pump
```

The implementation must test the race where an event is committed while the
pump is observing an empty page. Either the active invocation scans again or a
new invocation starts. The committed event cannot be stranded until process
restart.

Startup awaits the pump. EventStore signals request the same pump after local
command persistence and replicated promotion. UI command flows do not await it;
tests and maintenance code may explicitly await `pump()` for deterministic
catch-up. It returns no event or sequence information. No caller supplies
decoded event objects to projections.

### Failure behavior

A codec, registry, or projection handler failure is fatal. The pump finishes
waiting for every projection task already started for the page, stores the first
observed failure, and reads no next page. A failed projection handler leaves its
applying/scanned boundaries mismatched. Projections that completed the page
remain at the page end and are not rolled back. `onBatchApplied()` does not
throw.

The event store is the durable backlog, so no in-memory queue grows after a
failure. There is no in-process repair API. A later application start resets
inconsistent projections and resumes consistent projections from their stored
positions.

## Runtime lifecycle and pump-failure boundary

An internal `CqrsRuntimeLifecycle` owns runtime phases, admission checks,
transitions, and the first terminal pump failure. Lifecycle phases are not part
of the public API. The retained failure contains only the original pump error
and stack trace:

```dart
final class CqrsRuntimeFailure implements Exception {
  final Object error;
  final StackTrace stackTrace;
}
```

The public lifecycle surface includes:

```dart
CqrsRuntimeFailure? get failure;
Stream<CqrsRuntimeFailure> get failures;
Future<void> close();
```

`failures` is a broadcast stream and subscription is optional. Only failures
from actual `EventPump.pump()` calls, including startup, signal-driven,
explicit, and rebuild pumping, are terminal. The same
`CqrsRuntimeFailure` is stored and emitted once. Later operations on a failed
running runtime return that stored failure. Lifecycle misuse, including work
before initialization, calling `close()` during initialization, or work during
or after closure, throws `StateError` synchronously.

Command-handler exceptions and `Error`s, command encoding, persistence,
projection preparation, and projection reset failures propagate unchanged and
do not fail a running runtime. Initialization failures also propagate unchanged
unless startup pumping produced a `CqrsRuntimeFailure`; every initialization
failure automatically tears down and closes the runtime and initialization
cannot be retried.

`close()` is idempotent. Its first call stops accepting commands, pumps,
rebuilds, and synchronization work, then waits for every command admitted before
that boundary. It does not request a final pump. It cancels the EventStore
subscription, waits for remaining runtime maintenance, closes the failure
stream, and enters `closed`. Concurrent callers share that teardown and closure
does not replay a retained failure.

Closing does not reconstruct or restart a failed runtime. It closes the
runtime-owned `EventStore`, which closes its `EventDatabase`.

## Command execution

`CqrsRuntime` owns the authoritative command flow:

1. Create a command execution context backed by the event registry.
2. Run the command handler.
3. Serialize appended events.
4. Persist one `CommandChanges` batch.
5. Return after durable persistence succeeds.

The runtime exposes an API similar to:

```dart
await runtime.execute(
  command,
  input,
);
```

`execute()` returns `Future<void>`. It does not expose committed command IDs,
event IDs, local sequences, or projection progress. The EventStore signal
requests pumping after the commit, but `execute()` does not await the pump.
Commands are admitted only in `running`. Multiple admitted handlers may execute
concurrently; durable writes remain serialized where required by EventStore,
and conflicting stream versions produce `ConcurrencyProblem` without failing
the runtime.

Consistent projection selection is removed. `BoundCommand`, its consistent and
eventual projection lists, and direct live-event routing are deleted. Application
UI observes read-model changes through `onBatchApplied()` notifications.

Command-handler exceptions and `Error`s, concurrency rejection, encoding
failures, and persistence failures remain command failures and do not fail the
runtime.

Commands that produce no events do not request projection work, are not
persisted, and are not replicated.

## Listenable read models

CQRS provides the page boundary, not a UI framework. A projection that owns a
listenable read model calls its application notifier from `onBatchApplied()`.
Controllers subscribe to that notifier and reload their query when necessary.

Every independently observable read model may own its own application notifier.
In Notes, only `ResolvedNoteReadModel` has one. `NoteProjection.onBatchApplied()`
signals that notifier. `SearchProjection.onBatchApplied()` remains empty:
updating the search index does not force the UI to query and display the current
search again, while the next user-initiated search reads the available index.

`NoteListController` subscribes to the resolved-note notifier. If another
notification arrives during a reload, it marks another reload as pending and
runs it after the active reload. This coalesces work without a timer or debounce
and cannot lose the final resolved-note state. Disposal removes the listener.
Local commands and replicated events therefore update the note list through the
same application listener path.

Command completion continues to mean durable persistence, not read-model
visibility. Tests and maintenance flows call `pump()` explicitly whenever they
need deterministic projection state.

## Event-store contract changes

In the final runtime design, `EventStore.saveChanges` returns `Future<void>`.
Success means that the command and its events are durable. Their allocated
identities and local sequences stay inside the database and are available
through durable readers when needed. The current Stage 5 implementation still
returns `SaveChangesResult` because direct live delivery needs committed local
sequences. Stage 7 changes the return type and removes append-order
reconstruction with the direct-delivery path.

Pending promotion retains a success/not-ready result because the sync scheduler
needs to know whether promotion happened. It does not return event objects for
projection delivery.

EventStore exposes a broadcast applied-change signal:

```dart
Stream<void> get appliedChanges;
```

A successful local append or replicated promotion emits after commit. A failed
write, a not-ready promotion, and a command with no events do not emit. The
signal carries no records and cannot change the result of an already committed
write. `CqrsRuntime` subscribes before its initial startup pump, requests its
single-flight pump for every signal, and cancels the subscription in `close()`.

## Replication boundary

The sync engine remains separate from `CqrsRuntime` and reads durable records
from `EventStore`. A notification means only that new exportable or projectable
records may exist.

For outbound replication, the sender's receiver-local command sequence is a
useful per-peer paging cursor and ordering hint. Commands are the atomic causal
unit, and event index orders events inside a command. The sender-local sequence
is not persisted as the receiver's order and is not used to resolve concurrency.

The receiver continues to stage records idempotently and promotes a command only
when its origin order, dependency, and complete indexed event set are ready.
Promotion assigns new receiver-local sequences and requests the same event pump.

Fresh-device and distant-peer synchronization need a separate protocol plan.
The runtime rework should make that protocol easier to integrate, but it does
not define or claim it.

### Stage 9 device-identity translation

Stage 9 adds a concrete identity store for deterministic tests:

```dart
abstract interface class DeviceIdentityDatabase {
  Future<int?> getLocalId(String universalId);
  Future<String?> getUniversalId(int localId);
  Future<void> add(String universalId, int localId);
}

final class DeviceIdentityStore {
  Future<int?> getLocalId(String universalId);
  Future<String?> getUniversalId(int localId);
  Future<void> add(String universalId, int localId);
}

final class MemoryDeviceIdentityDatabase
    implements DeviceIdentityDatabase {
  // String -> int map
  // int -> String map
}
```

The memory database uses two maps for constant-time lookup in both directions.
Adding an existing identical pair is idempotent. Reusing either the universal
ID or local ID for a different pair is rejected.

Each registered runtime receives its own `DeviceIdentityStore`. Registration
maps that runtime's non-empty universal string ID to database-local device ID
zero. Previously unseen remote universal IDs receive positive local IDs chosen
by `TestSyncSystem`, then recorded explicitly through `add`. Mappings are not
shared between runtimes.

Export translates the device component of every local command ID, event ID,
and dependency-vector key from its local integer through the source identity
store to a universal string. Import resolves every universal string through the
destination identity store, allocating a positive local ID when necessary.
This includes identities learned indirectly when records from a third device
are relayed.

### Stage 9 test synchronization

Stage 9 introduces only this test utility:

```dart
final class TestSyncSystem {
  void register(String universalId, CqrsRuntime runtime);

  Future<void> sync(String from, String to);
  Future<void> syncAll();
  Future<void> close();
}
```

There is no `SyncSystem` interface, `MemorySyncSystem`, registration handle, or
automatic synchronization. Registration requires a running runtime and a
unique, non-empty universal ID. Not calling `sync` represents an offline
period. The utility has no connectivity state, connect or disconnect methods,
queue, timer, or retry behavior.

`sync(from, to)` is asynchronous and one-way. It acquires exclusive
synchronization access to both runtimes in stable universal-ID order. The
writer-preferred gate blocks new commands and waits for active handlers before
the utility reads or imports records, preventing command/sync starvation and
ensuring the operation sees a stable invocation boundary.

The operation pages every source applied command needed at invocation time,
loads its applied events, translates all device identities, and constructs
translated `ReplicatedCommand` and `ReplicatedEvent` objects. It passes those
objects directly to the destination. No record serialization, packet, or
envelope type is introduced, and the existing `EncodedCommand` and
`EncodedEvent` objects inside the records are preserved.

The destination stages command metadata and events through the existing
EventStore APIs and repeatedly promotes as dependencies become ready. `sync`
completes only after all source records needed at its invocation boundary have
been delivered and their commands promoted by the destination. Projection
pumping remains a separate explicit operation.

`syncAll()` synchronizes every ordered runtime pair repeatedly until no runtime
gains another applied command. This provides deterministic memory-only delivery
for tests, including relayed dependencies. Delivery is assumed to succeed, so
there are no retry, backoff, transport-error, or partial-network policies.
Duplicate delivery relies on the existing idempotent staging behavior.

`close()` prevents new sync calls and awaits active synchronization work. It is
idempotent and does not close registered runtimes, identity stores, or their
storage. Production synchronization intentionally inherits no interface from
this utility. Its transport, lifecycle, durable cursors, identity,
authentication, retries, resource bounds, and protocol remain a separate Stage
10 design.

## Migration strategy

This is a breaking rewrite, but it should still be split into testable stages.
There will be no public compatibility layer. Each stage migrates its affected
callers and removes the replaced code before it is complete.

### Stage 0: Lock down behavior

- Add characterization tests for local command persistence, startup replay,
  command completion, projection failure, pagination, and promoted events.
- Write pump-specific race tests before changing live dispatch.
- Record which current APIs and files will be deleted at cutover.

Gate: the existing implementation remains unchanged and the new behavioral
expectations are executable.

Stage 0 is complete. The characterization suite records local command
persistence and completion, startup replay across event pages, projection
failure handling, eventual-dispatch boundary races, and replay of promoted
events. The EventStore contract suite separately covers local persistence,
pagination, promotion readiness, and atomic visibility for both memory and
SQLite databases.

The following current APIs and files are scheduled for deletion at the Stage 7
cutover. This is an inventory, not permission to remove them in an earlier
stage:

- `BoundCommand`, `BoundCommandFn`, and
  `lib/src/cqrs/cqrs_runtime/bound_command.dart`.
- `CqrsRuntime.bindCommand`, its consistent-projection argument, and the
  consistent/eventual runner split in
  `lib/src/cqrs/cqrs_runtime/cqrs_runtime.dart`.
- `ProjectionRouter` and
  `lib/src/cqrs/projection/projection_router.dart`.
- `ProjectionSink` and `lib/src/cqrs/projection/projection_sink.dart`.
- `ProjectionRuntime.enqueue`, `enqueueApplied`, `shouldProcess`,
  `shouldProcessString`, its `AsyncFIFOQueue`, `QueueItem`, and the direct live
  event dispatch path in
  `lib/src/cqrs/projection/projection_runtime.dart`.
- `EventEnvelope` and `lib/src/cqrs/event/event_envelope.dart`, after command
  execution no longer reconstructs live event objects from persistence
  results.
- `SaveChangesResult`, `StreamAppendOrder`, and the append-order reconstruction
  in `CommandExecutor` when `EventStore.saveChanges` becomes `Future<void>`.
- `ProjectionFailureHandler`, `StandardProjectionFailureHandler`,
  `ThrowingProjectionFailureHandler`, and their files when failures move to the
  terminal `CqrsRuntimeFailure` boundary.
- `CqrsRuntimeV2Idea` and
  `lib/src/cqrs/cqrs_runtime/CqrsRuntimeV2Idea.dart`.

Tests and application callers tied exclusively to these APIs are migrated or
deleted with their owner. The stream-ID, codec, and old projection-shape files
are inventoried by Stages 1-3 and removed in those stages rather than waiting
for the runtime cutover.

### Stage 1: Replace stream identity terminology

- Replace `StreamIdPattern` with `StreamRoute` and its all/wildcard variants.
- Replace ID/data terminology with `streamPath` and `streamParams`.
- Introduce `buildPath`, `parseParams`, and path-only matching.
- Rename affected Dart paths, application constants, records, locks, tests, and
  SQLite schema columns.
- Remove every old stream-ID route symbol and path.

Gate: the workspace uses route/path/params terminology exclusively.

Stage 1 is complete. `StreamRoute`, `StreamRouteAll`, and
`StreamRouteWildcard` now expose `buildPath`, `parseParams`, and path-only
`matches`. Command state and locks, runtime event envelopes, projection
routing, durable event records, EventStore databases, test utilities, and
application callers use `streamPath` and `streamParams`. The SQLite event
schema uses `stream_path`; existing development databases are not migrated.
All old stream-ID route source files, imports, symbols, and application paths
were removed without aliases.

### Stage 2: Replace event codecs with the registry

- Introduce the singular `EventCodec<T>` and internal event registry.
- Register every application and test event codec centrally.
- Change command streams to encode through the registry.
- Change command-stream reads and projection replay to decode through the
  registry.
- Remove the current event-family codec API and projection codec properties.
- Remove old codec imports, implementations, and test helpers.

Gate: commands and existing replay behavior pass through one registry, with no
old codec API remaining.

Stage 2 is complete. `EventCodec<T>` now owns one stable persisted kind and
converts only between its concrete event type and bytes. The event registry
validates additions, encodes by Dart event type, and decodes by persisted kind.
The application assembles it and passes it into `CqrsRuntime`; commands,
command-stream reads, live projection delivery, and projection replay all use
that injected instance. Notes and finance add one codec per concrete event
centrally. Event-family codecs, projection-owned codecs, command-stream codec
arguments, and codec-based test helpers were removed. Command execution and
live envelopes retain only encoded events, so typed stream parameters and
original event objects no longer travel through the direct dispatch path.

### Stage 3: Introduce typed projections

- Add projection name, version, reset, required batch callback, and one typed
  `StreamRoute` and event handler.
- Support `Projection<Object, TParams>` for manual runtime-type checks.
- Validate names, versions, and stream route definitions.
- Migrate all projections and remove the temporary route-list shape.

Gate: existing projections behave the same through their single route, and a
test `Projection<Object, TParams>` consumes unrelated decoded event types.

Stage 3 is complete. `Projection` now declares a globally unique name, a
positive model version, one typed `StreamRoute`, one typed `apply` handler,
reset behavior, and the required batch callback. `Projection<Object, TParams>`
supports the rare handler that checks decoded runtime types manually. Runtime
registration rejects empty and duplicate projection names, surrounding name
whitespace, non-positive versions, and empty stream route patterns.
The existing runtime does not yet define page batches; production invocation of
`onBatchApplied()` arrives with the pump in Stages 6-7.

### Stage 4: Change runtime-store projection state

- Persist projection version and scanned-through boundaries per projection.
- Advance progress through skipped events and empty route batches.
- Write applying/scanned progress once at the start and end of each projection
  page while projection handlers retain per-event read-model writes.
- Preserve interrupted-page detection.
- Add selective reset, changed-version reset, and restart tests for memory and
  SQLite runtime databases.
- Remove the application-wide runtime migration version if it has no remaining
  responsibility.

Gate: projections independently resume, rebuild, and advance through pages.

Stage 4 is complete. RuntimeStore now persists each projection's positive
version plus applying-through and scanned-through local sequence boundaries.
Initialization resets only missing, changed, or interrupted projections and
resumes consistent matching versions. The legacy startup path creates an
independent applied-event reader for each projection, applies matching events
sequentially, and advances progress to every page end with two RuntimeStore
writes per projection page. Memory and SQLite contract tests cover the progress
protocol, and restart tests reuse memory state and reopen SQLite storage while
adding, changing, and interrupting one of two projections. The application-wide
global migration counter, migration policy, storage operations, schema, and
Notes wiring were removed. Existing development runtime databases are not
migrated.

### Stage 5: Prepare EventStore signaling and the event source

- Retain only the promotion result needed by sync scheduling.
- Provide the unfiltered paginated applied-event source needed by the pump.
- Verify monotonic receiver-local sequence behavior for local saves and remote
  promotions.
- Add the broadcast `appliedChanges` signal after successful append/promotion.

Gate: a test can commit and promote events and recover their complete ordered
history only from the durable source.

The durable portion of Stage 5 is complete. `getAppliedEventReader` exposes the
complete applied-event history in exclusive receiver-local sequence pages, and
`appliedChanges` broadcasts once after each successful non-empty local append
or pending-command promotion. Memory and SQLite contract tests cover page
boundaries, interleaved local and promoted ordering, broadcast delivery to
multiple test subscribers, subscriber-side durable reads, and no-signal
outcomes. Stage 7 now consumes the signal in production and removed the
temporary append-order save result.

### Stage 6: Build the pump as an isolated vertical slice

- Implement single-flight paging, decoding, routing, per-projection batching,
  and page barriers behind test-oriented collaborators.
- Test projections at different positions.
- Test a page with no matches.
- Test an `Object` projection with unrelated decoded event types.
- Test an event routed to multiple projections.
- Test concurrent projection processing with sequential calls inside each
  projection.
- Test codec and projection failures as terminal runtime failures.
- Test events committed during active drain and at the empty-page boundary.
- Assert that no more than one page is in flight.

Gate: the pump is fully testable without command handlers or an application.

Stage 6 established the pump as an isolated vertical slice. `EventPump` creates
a fresh reader for each requested scan from the minimum prepared projection
position, decodes each durable event once, processes projection pages
concurrently behind a page barrier, and coalesces concurrent requests without
losing active-processing or empty-read wakeups. Typed page adapters keep each
projection sequential, advance scanned progress through unmatched pages, and
invoke the batch callback once after committed progress for matched pages. The
pump rethrows the first page failure, including `Error`, after all started
projection work settles, and never reads a later page in that scan. Focused
tests cover positions, routing and typing, decode count, ordering and barriers,
wakeup races, callbacks, terminal failures, and empty projection lists.

Stage 7 integrated this slice into `CqrsRuntime`.

`ProjectionRegistry.prepare` owns selective reset and durable page-adapter
construction for the production pump.

### Stage 7: Perform the runtime cutover

- Replace current command-owned routing with `CqrsRuntime.execute`.
- Freeze the injected event and projection registries synchronously when
  single-flight initialization begins.
- Change local save to `Future<void>` and remove `SaveChangesResult`,
  `StreamAppendOrder`, and append-order reconstruction.
- Accept concurrent commands only while running, with EventStore locking and
  optimistic stream checks preserving the durable boundary.
- Make startup and EventStore signals use the same public single-flight pump;
  serialize projection rebuilds with pumping and retain a trailing scan request.
- Add internal runtime lifecycle handling, stored pump-only
  `CqrsRuntimeFailure`, optional failure stream subscription, and idempotent
  non-pumping `close()` teardown.
- Migrate application wiring and command call sites.
- Give only `ResolvedNoteReadModel` a Notes notifier, signal it from
  `NoteProjection.onBatchApplied()`, and keep
  `SearchProjection.onBatchApplied()` empty.
- Make `NoteListController` subscribe, dispose its subscription, and coalesce
  active/pending reload requests without CQRS debounce.
- Remove `ProjectionRouter`, direct runtime-event dispatch, consistent/eventual
  routing, obsolete projection queues, and `BoundCommand`.
- Remove `CqrsRuntimeV2Idea` and any other superseded prototype code.
- Scan for every old symbol, import, and path.
- Replace the isolated pump's temporary catch-all boundary with the public
  runtime failure wrapper recorded in `CONVENTIONS.md`.

Gate: there is exactly one projection-delivery path in production code.

Stage 7 is implemented. Commands and promoted events reach projections only
through durable applied history and `EventPump`. The runtime owns registry
freezing, initialization, signal-driven and explicit pumping, serialized
rebuilds, terminal pump-failure identity, and shutdown. Finance and Notes use
`execute`; Notes notifies only its resolved-note read model and coalesces UI
reloads. Removed direct-delivery APIs and their queue dependency are not kept as
compatibility paths.

### Stage 8: Validate the complete migration

- Run root dependency resolution if package dependencies changed.
- Run workspace listing, root analysis, relevant focused tests, and the complete
  Melos test suite.
- Run stale symbol, stale path, and compatibility alias searches.
- Verify projection rebuild and restart with both memory and SQLite stores.
- Verify local commands and promoted replicated commands produce identical pump
  behavior.
- Verify commands complete after persistence while the public pump provides
  deterministic catch-up for tests.
- Test lifecycle admission, one-shot initialization, rejected closure during
  initialization, single-flight pumping, synchronous registration freezing,
  concurrent command admission, rebuild/pump exclusion, and trailing scans.
- Test raw initialization, command, encoding, persistence, preparation, and
  reset failures. Verify that only startup and running pump failures are stored
  and returned by identity, while lifecycle misuse throws synchronous
  `StateError`.
- Test idempotent close, rejection of new work, admitted-command draining,
  absence of shutdown pumping, subscription cancellation, maintenance draining,
  failure-stream closure, and runtime ownership of the injected event database.
- Test resolved-note notification after matched batches, no notification after
  unmatched batches, lossless active/pending controller reloads, listener
  disposal, and that search projection updates do not redisplay search results.
- Verify command completion can precede read-model visibility and explicit
  `pump()` makes projection state deterministic.
- Update source-backed repository and package documentation to describe only the
  implemented behavior.

Gate: all old runtime paths are gone and all validation passes.

Stage 8 is implemented. Root dependency resolution, workspace discovery,
analysis, focused CQRS and Notes tests, and the complete Melos suite pass.
Memory and SQLite projection rebuild coverage passes, and stale symbol, path,
and compatibility-alias scans find no implementation references to removed
runtime paths. Source-backed repository documentation describes the durable
pump, lifecycle, projection progress, and the absence of synchronization.

### Stage 9: Add deterministic test synchronization

- Add `DeviceIdentityDatabase`, `DeviceIdentityStore`, and
  `MemoryDeviceIdentityDatabase` with bidirectional lookup and conflict checks.
- Add the writer-preferred runtime gate used by exclusive sync access.
- Add `TestSyncSystem` with explicit registration, one-way `sync`, fixed-point
  `syncAll`, and non-owning `close`.
- Translate local integer identities to universal strings during export and
  into each destination's independent integer namespace during import.
- Transfer translated runtime records directly, preserving their encoded
  command and event objects, and use existing staging and promotion APIs.
- Keep projection pumping explicit and separate from sync completion.
- Do not add production interfaces, automatic sync, connectivity state,
  transport models, serialization, timers, queues, retries, or security claims.
- Test forward and reverse identity lookup, idempotent pair insertion, conflicts,
  local ID zero, positive remote allocation, and independent runtime mappings.
- Test command/sync exclusion and writer preference.
- Test one-way sync, reverse sync, `syncAll`, no transfer without an explicit
  call, encoded-object preservation, dependency translation, third-device relay,
  duplicate delivery, promotion, and completion before explicit projection
  pumping.

Gate: independent runtimes can exchange deterministic in-memory test records
only when the test explicitly requests it, without implying a production sync
capability.

### Stage 10: Design production synchronization separately

- Design transport and lifecycle independently from `TestSyncSystem`.
- Define durable peer cursors, versioned wire records, batching, missing
  dependency requests, promotion scheduling, retries, reconnect behavior,
  identity, authentication, resource bounds, and protocol evolution.
- Use sender-local command sequence only as a paging hint and preserve
  receiver-local ordering.
- Define and test application convergence separately from record delivery.
- Make no convergence, security, backup, or availability claims beyond
  implemented and validated behavior.

This stage intentionally receives no interface or transport abstraction from
the Stage 9 test utility.

## Why not migrate everything in one step?

The final runtime cutover is necessarily cross-cutting, and Stage 7 may be one
large change. The foundations should still be established first because codec
lookup, route typing, projection progress, EventStore signaling, and pump races
can each be tested independently.

The stages are not compatibility periods. They are clean internal migrations
that keep the repository understandable and make failures attributable. If a
stage cannot leave the workspace compiling without a temporary public bridge,
combine it with the next stage rather than retaining obsolete APIs.

## Deferred optimizations

- Route by persisted kind and path before decoding events no projection needs.
- Batch projection repository writes where their atomicity permits it.

Each optimization must preserve the durable reader fallback and single-flight
ordering semantics.
