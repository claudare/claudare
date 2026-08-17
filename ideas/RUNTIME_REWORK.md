# CQRS runtime rework plan

Status: decision-complete design proposal. Stages 0-3 are implemented; Stages
4-9 remain future work. Nothing in those later stages should be treated as
implemented behavior until the source and repository documentation say so.

This is a clean development migration. The implementation does not need
backwards-compatible APIs, aliases, adapters, or parallel old and new runtime
paths. Replaced code and concepts should be removed completely during the
cutover.

## Motivation

The current live event path is centered on `BoundCommand`. Events produced by a
command are persisted and then passed directly to selected projection queues.
Startup replay and future replicated-command promotion use different paths.
This makes the runtime harder to reason about and creates several places where
ordering, decoding, catch-up, and projection failure behavior can diverge.

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
- Event serialization is registered once with the runtime.
- A projection may define multiple typed routes with different event families
  and `StreamRoute` values.
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

During `configuring`, callers may register event codecs and projections. During
`initializing`, the runtime freezes registration, initializes stores, validates
the registry, prepares projections, and catches them up. Commands cannot run
until initialization succeeds.

A failed runtime is terminal. It stops pumping, rejects later commands, and is
never automatically repaired, restarted, or reconstructed. The application may
show an error screen or banner. `close()` cancels subscriptions and releases
runtime-owned resources; it is also useful for tests.

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
`parseParams(streamPath)` for matching routes.

## Event codecs and registry

Each persisted event kind has one codec:

```dart
abstract interface class EventCodec<T extends Object> {
  String get kind;

  Uint8List toBytes(T event);
  T fromBytes(Uint8List bytes);
}
```

The runtime registers codecs before initialization:

```dart
runtime.registerEvent<AccountOpened>(AccountOpenedCodec());
runtime.registerEvent<AccountRenamed>(AccountRenamedCodec());
```

The internal registry maps:

- Stable persisted kind to a decoder.
- Dart event type to an encoder.

Registration must reject empty kinds, duplicate kinds, and duplicate Dart event
types. Persisted kinds are explicit protocol identifiers and must not be derived
from `runtimeType.toString()`.

Codec exception translation remains centralized at the codec boundary. Unknown
kinds and decoded values with an unexpected type are explicit runtime or
projection failures. They must not be silently skipped.

Any event or command encoding failure is a fatal runtime failure, even though no
invalid event was committed. A durable event that cannot be decoded is also a
fatal runtime failure.

`CommandContext` and `CommandStream` use the registry supplied by the runtime.
Commands no longer carry an event-family codec when opening a stream. Appending
an event encodes it immediately into an `EventAppend`. The runtime does not keep
the original event object for direct projection delivery.

## Projection model

A projection owns one read model, one name, one version, one reset operation,
one or more event routes, and a page-completion callback:

```dart
abstract interface class Projection {
  String get name;
  int get version;

  List<ProjectionRoute> get routes;

  Future<void> reset();
  void onBatchApplied();
}
```

`ProjectionRoute<TEvent, TParams>` keeps the application handler typed while
the runtime consumes routes through their common `Object` boundary:

```dart
ProjectionRoute<AccountEvent, AccountParams>(
  streamRoute: accountStreamRoute,
  apply: projection.applyAccountEvent,
);

ProjectionRoute<UserEvent, String>(
  streamRoute: userStreamRoute,
  apply: projection.applyUserEvent,
);
```

This allows one projection to listen to multiple stream patterns and unrelated
event families. The runtime decodes through the event registry, checks the
decoded event and parsed stream parameters, and then calls the typed handler.

A sealed event family remains useful within an individual typed route because
the route handler can use an exhaustive switch. It is not required that every
route in a projection share that family.

When a handler needs runtime dispatch rather than a sealed event family, it uses
`ProjectionRoute<Object, TParams>` and checks the decoded object's runtime type
itself.

An event may match more than one route in the same projection. Every matching
route runs once in route registration order. Tests should cover intentional
overlap so that a broad pattern does not accidentally duplicate a narrow
handler.

`onBatchApplied()` is required, but projections that do not notify an
application listener may leave it empty. The pump calls it once after the
projection has successfully processed a page containing at least one matching
event and stored its scanned-through boundary. It is not called for a page with
no matching events. CQRS does not depend on Flutter `Listenable`; an application
projection may call an application-owned notifier from this method.

## Projection version and progress

Runtime version is not application version. Each projection declares its own
positive model version. `RuntimeStore` persists at least:

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
3. Matches the decoded event and `streamPath` against projection routes.
4. Builds an ordered set of route calls for each projection.
5. Marks each projection as applying through the page end.
6. Runs that projection's matching route calls sequentially.
7. Marks the projection as scanned through the page end, including when it had
   no matching route calls.
8. Calls `onBatchApplied()` if the projection had matching events.
9. Waits for every projection task before reading another page.

Projections process the page concurrently. Calls within one projection remain
sequential in increasing `localSequence`; matching routes for one event run in
route registration order. Successful projections may store progress and notify
before another projection fails. The pump still waits for every projection task
started for the page to settle before handling the result.

RuntimeStore writes projection progress only at the start and end of a page.
Projection handlers may perform whatever per-event read-model writes they need.
If five events match, the projection may write five times while RuntimeStore
writes only the applying and scanned-through boundaries. This is the intended
page recovery unit, not a deferred storage-transaction requirement.

This keeps memory bounded to approximately one event page and its route calls.
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

A codec, registry, projection handler, or batch callback failure is fatal. The
pump finishes waiting for every projection task already started for the page,
stores the first observed failure, and reads no next page. A failed projection
handler leaves its applying/scanned boundaries mismatched. Projections that
completed the page remain at the page end and are not rolled back.

The event store is the durable backlog, so no in-memory queue grows after a
failure. There is no in-process repair API. A later application start resets
inconsistent projections and resumes consistent projections from their stored
positions.

## Runtime failure boundary

The runtime exposes its state and one nullable terminal failure:

```dart
enum CqrsRuntimeState {
  configuring,
  initializing,
  running,
  failed,
  closing,
  closed,
}

final class CqrsRuntimeFailure implements Exception {
  final Object error;
  final StackTrace stackTrace;
}
```

The public lifecycle surface includes:

```dart
CqrsRuntimeState get state;
CqrsRuntimeFailure? get failure;
Stream<CqrsRuntimeFailure> get failures;
Future<void> close();
```

`failures` is a broadcast stream and subscription is optional. The first fatal
failure stores only the original object and stack trace. The same
`CqrsRuntimeFailure` is stored and emitted once. Later `execute()` and `pump()`
calls throw that stored failure.

This boundary intentionally contains every thrown object, including Dart
`Error`, so the application can fail gracefully with an error screen. This is a
new explicit exception to the repository's ordinary fatal-`Error` convention
and must be recorded in `CONVENTIONS.md` during implementation. Codec-safe
translation remains a separate defense against invalid encoding and decoding.

If `onBatchApplied()` throws, projection data and scanned progress remain
committed because the callback runs after the end boundary. The outer runtime
boundary records the callback failure and stops the runtime; the callback does
not contain or translate its own failure.

`close()` stops accepting work, cancels the EventStore subscription, waits for
active runtime work to settle, closes the failure stream, and enters `closed`.
It does not reconstruct or restart a failed runtime.

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

Consistent projection selection is removed. `BoundCommand`, its consistent and
eventual projection lists, and direct live-event routing are deleted. Application
UI observes read-model changes through `onBatchApplied()` notifications.

Expected domain command exceptions and concurrency rejection remain command
failures and do not fail the runtime. Event or command encoding failures,
unexpected persistence failures, and fatal thrown objects transition the runtime
to `failed`.

Commands that produce no events do not request projection work, are not
persisted, and are not replicated.

## Listenable read models

CQRS provides the page boundary, not a UI framework. A projection that owns a
listenable read model calls its application notifier from `onBatchApplied()`.
Controllers subscribe to that notifier and reload their query when necessary.

If another notification arrives during a reload, application code marks another
reload as pending and runs it after the current reload. This coalesces work
without a timer or debounce and cannot lose the final read-model state. Local
commands and replicated events therefore update the UI through the same
application listener path.

## Event-store contract changes

`EventStore.saveChanges` returns `Future<void>`. Success means that the command
and its events are durable. Their allocated identities and local sequences stay
inside the database and are available through durable readers when needed.

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
converts only between its concrete event type and bytes. The internal event
registry validates registrations, encodes by Dart event type, and decodes by
persisted kind. Commands, command-stream reads, live projection delivery, and
projection replay all use the runtime-owned registry. Notes and finance
register one codec per concrete event centrally. Event-family codecs,
projection-owned codecs, command-stream codec arguments, and codec-based test
helpers were removed. Command execution and live envelopes retain only encoded
events, so typed stream parameters and original event objects no longer travel
through the direct dispatch path.

### Stage 3: Introduce projections and typed routes

- Add projection name, version, reset, required batch callback, and typed routes.
- Support multiple typed routes and `StreamRoute` values per projection.
- Support `ProjectionRoute<Object, TParams>` for manual runtime-type checks.
- Validate names, versions, route definitions, and route overlap behavior.
- Migrate all projections and remove the old single-pattern projection shape.

Gate: existing projections behave the same through route registrations, and a
test projection consumes two unrelated typed routes.

Stage 3 is complete. `Projection` now declares a globally unique name, a
positive model version, an ordered route list, reset behavior, and the required
batch callback. The single generic `ProjectionRoute<TEvent, TParams>` keeps
event and stream-parameter types at the handler boundary, including
`ProjectionRoute<Object, TParams>` when a handler checks decoded runtime types
manually. Projection runners decode once, invoke every matching route in
registration order, and support unrelated event families and stream routes
within one projection. Runtime construction rejects empty and duplicate
projection names, non-positive versions, empty route lists, and empty patterns.
The old projection-level event and stream-parameter generics and single
`streamRoute`/`apply` shape were removed.
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

### Stage 5: Prepare EventStore signaling and the event source

- Change local save to `Future<void>` and remove append-order reconstruction.
- Retain only the promotion result needed by sync scheduling.
- Provide the unfiltered paginated applied-event source needed by the pump.
- Verify monotonic receiver-local sequence behavior for local saves and remote
  promotions.
- Add the broadcast `appliedChanges` signal after successful append/promotion.

Gate: a test can commit and promote events and recover their complete ordered
history only from the durable source.

### Stage 6: Build the pump as an isolated vertical slice

- Implement single-flight paging, decoding, routing, per-projection batching,
  and page barriers behind test-oriented collaborators.
- Test projections at different positions.
- Test a page with no matches.
- Test multiple routes in one projection.
- Test an event routed to multiple projections.
- Test concurrent projection processing with sequential calls inside each
  projection.
- Test codec, projection, and batch-callback failures as terminal runtime
  failures.
- Test events committed during active drain and at the empty-page boundary.
- Assert that no more than one page is in flight.

Gate: the pump is fully testable without command handlers or an application.

### Stage 7: Perform the runtime cutover

- Replace current command-owned routing with `CqrsRuntime.execute`.
- Make startup and EventStore signals use the same public single-flight pump.
- Add terminal runtime state, stored `CqrsRuntimeFailure`, optional failure
  stream subscription, and `close()`.
- Migrate application wiring and command call sites.
- Migrate application read models to listenable callbacks triggered by
  `onBatchApplied()`; coalesce application reload requests without CQRS debounce.
- Remove `ProjectionRouter`, direct runtime-event dispatch, consistent/eventual
  routing, obsolete projection queues, and `BoundCommand`.
- Remove `CqrsRuntimeV2Idea` and any other superseded prototype code.
- Scan for every old symbol, import, and path.
- Document the runtime fatal boundary in `CONVENTIONS.md`.

Gate: there is exactly one projection-delivery path in production code.

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
- Verify a projection failure stops before the next page and later calls throw
  the stored runtime failure.
- Update source-backed repository and package documentation to describe only the
  implemented behavior.

Gate: all old runtime paths are gone and all validation passes.

### Stage 9: Design replication scheduling separately

- Define peer cursors, export pages, command/event batching, missing dependency
  requests, promotion scheduling, retries, and reconnect behavior.
- Use sender-local command sequence only as a hint.
- Test different valid receiver-local orders for concurrent commands.
- Make no convergence or security claims beyond implemented behavior.

This stage is intentionally outside the runtime cutover.

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
