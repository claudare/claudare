# Claudare Implementation Study

## Method

This report is based on static inspection of the current Dart/Flutter source. No code, build, tests, database, migration, or application was executed. Test files are treated as evidence of intended coverage, not as proof that they currently pass.

Evidence labels:

- **Implemented**: an executable source path exists.
- **Test-described**: a test expresses the behavior, but was not run.
- **Prototype**: partial code exists but cannot provide the advertised feature.
- **Missing**: no implementation path was found.

## Package inventory

### `core`

`core` targets Dart `^3.7.2`. Its direct dependencies include `isolate_sqlite`, `messagepack`, WebSocket support, `sodium`, Pointy Castle, mutexes, UUIDs, and utility packages. Several are not used by an integrated production path.

The main implemented areas are:

- CQRS commands and stream access;
- memory and SQLite event stores;
- projection routing, replay, and checkpointing;
- runtime-version-driven projection rebuilds;
- random IDs and time providers;
- WebSocket byte transport;
- test utilities and a finance example.

The prototype areas are:

- replication types and causal/dependency helpers;
- text/value CRDTs;
- blob IDs, sizing, lifecycle events, and crypto constants;
- relay/direct sync message shapes.

### `notes_app_v0`

This is a Flutter application targeting the usual generated desktop, mobile, and web platforms. It depends on sibling `core` by path and on `isolate_sqlite` Git ref `0.3.1`.

It implements:

- create, title update, content update, trash, and restore note commands;
- JSON event codecs;
- an event-backed note projection in `notes.db`;
- an eventual FTS5 search projection in `search.db`;
- projection rebuild and database reset controls;
- a simple note editor/list UI.

It does not use the sync, blob, or text CRDT prototypes.

### `isolate_sqlite`

The sibling package targets Dart `^3.11.3`, whereas `core` and the app declare `^3.7.2`. More importantly, the other packages reference the Git dependency, not this sibling path.

The wrapper owns SQLite in a dedicated isolate. The public caller sends synchronous functions that receive `SyncContext`; the worker returns values or reconstructed errors. Transactions are explicit `BEGIN`/`COMMIT` with rollback on callback failure.

## End-to-end note trace

### Startup

1. `main.dart` constructs `ProductionApplicationFactory` and mounts `LoadingScreen`.
2. The factory creates two `IsolateSqlite` instances, a `SqliteEventStore`, `SqliteRuntimeRepo`, note projection/read model, and search projection/read model.
3. `Application.initialize` opens `notes.db` and `search.db` in the application support directory.
4. The event-store migration creates `stream` and `event` tables.
5. `NotesRuntime.initialize` initializes the runtime repository and projections.
6. If stored runtime version differs from `NotesRuntime.runtimeVersion == 7`, projections reset.
7. Note and search projections replay matching events from their checkpoints.
8. The runtime version is stored after catch-up.
9. The loading screen attempts three hard-coded commands for note ID `test`, swallowing any error.

The application has no close/dispose path for either database isolate. `LoadingScreen.didChangeDependencies` can invoke initialization more than once if dependencies change; `Application.initialize` is not idempotent and opening an already-open database throws.

### Create or edit

1. `NoteController` buffers current full title/content strings in memory.
2. Focus loss or post-pop callback calls `flushChanges`.
3. A new note gets a 128-bit random Base64URL ID.
4. Commands call `mustNotExist` or `mustExist`, producing a stream version lock.
5. The command appends one JSON-encoded event.
6. `SqliteEventStore` transactionally inserts it and advances stream version.
7. The live event is enqueued to search and note projection runtimes.
8. The command waits for the note projection but not search.

The pop callback runs after navigation has already occurred and does not block it. The controller may be disposed while asynchronous flushing continues, so a final edit is not protected by a “save before leave” boundary.

### Replay

The note projection checkpoint is the maximum `_local_sequence` stored across note rows. Search keeps one explicit sequence row. `GlobalEventReader` requests filtered pages after that local sequence and projections decode/apply each event.

Event codecs have no general schema-version/upcaster abstraction. The note codec contains one manual compatibility alias from `note.deleted` to `note.trashed`; unknown kinds throw and place a projection into fatal state.

## Event-store implementation

### SQLite schema

The `stream` table stores one current version per stream. The `event` table stores local, stream, device, and causal sequences with opaque event bytes. SQLite views calculate the next numbers using `MAX(...) + 1` inside the write transaction.

Strengths:

- event bytes and stream version change in one transaction;
- version mismatch throws `ConcurrencyProblem`;
- stream reads and projection reads are paged and ordered;
- database reset deletes events and stream heads atomically.

Shortcomings:

- there is no stable event ID;
- no durable command table exists;
- `StoredCommandWrite` and `StreamAppends.dependencies` are ignored;
- no replicated-import transaction exists;
- no uniqueness constraints enforce device sequence or stream version;
- no foreign key links event rows to stream rows;
- only one stream can be changed per SQLite transaction;
- event payloads are plaintext;
- application ID is a `TODO` constant and absent from schema keys;
- statistics count only event detail bytes, not actual database size.

### Memory store parity

The memory store supports multi-stream appends and retains successful commands in memory, so it has behavior the SQLite production store lacks. Conversely, its projection pagination stops after one page because it always returns a null cursor. Tests that run against both stores cover empty projection reads, simple append/read, stream pagination, concurrency, reset, and approximate statistics, but not parity for multi-stream changes, command retention, dependencies, or non-empty projection pagination.

### Error adapter

`EventStoreSafe.saveChanges` awaits the underlying future and wraps errors. Its other methods return futures directly from inside synchronous `try` blocks. Asynchronous failures therefore bypass the promised `EventStoreException` translation. The adapter is inconsistent exactly where storage errors are most likely to be asynchronous.

## Projection implementation

`ProjectionRuntime` applies catch-up events directly and live events through `AsyncFIFOQueue`. Projection failures are captured rather than thrown through the command. “Consistent” means the command waits until the projection callback completes; it does not mean event and read-model writes share a transaction.

Notable limitations:

- eventual projection completion has no await/drain API; the finance test uses a fixed 10 ms delay;
- queue reset cannot cancel an in-flight apply, resets sequence state immediately, and does not complete the callback for the already-removed current item;
- runtime reset/catch-up is not coordinated with incoming commands;
- catch-up has no progress, cancellation, or bounded recovery mode;
- a single invalid/unknown event permanently disables a projection instance;
- setting the runtime version occurs after catch-up futures return, without an explicit check that all failure handlers remain healthy.

The note projection is waited for by every note command. Search is eventual and stored in a separate database. A crash can therefore leave search behind, but its checkpoint permits replay on restart.

## Notes conflict behavior

`NoteProjection` implements different semantics per field:

| Field        | Current merge                                           | Distributed result                                                  |
| ------------ | ------------------------------------------------------- | ------------------------------------------------------------------- |
| Title        | Greatest event wall-clock timestamp; incoming wins ties | Vulnerable to clock skew and arrival-order divergence on ties       |
| Content      | Full replacement in local-sequence replay order         | Diverges if peers import concurrent replacements in different order |
| Trash state  | Latest locally applied trash/restore                    | Diverges under concurrent trash/restore                             |
| Created time | Timestamp of create event                               | Stable only if exactly one accepted create exists                   |
| Updated time | Timestamp of last locally applied title/content event   | Can move backward and can disagree with the winning title           |

`CreateNote.mustNotExist` and per-stream optimistic locks prevent two local creates in the same store. They do not define how concurrent creates or edits from independent devices merge.

## Search implementation

Search uses FTS5 with prefix terms, BM25 weighting, and timestamp tie ordering. Title and content updates replace the relevant FTS row and advance an explicit checkpoint in the same search-database transaction.

Issues:

- note create, trash, and restore are no-ops and do not advance the search checkpoint, causing repeated replay of trailing no-op events;
- `getManyById` uses `WHERE id IN (...)` without preserving FTS result order, so ranked results can be returned in arbitrary database order;
- the requested `ResolvedNoteQueryOrder` is ignored for non-empty searches;
- “favorited” returns no rows in the normal note query but returns all search matches in `CompositeNoteSearch`;
- trash filtering occurs after fetching matches;
- rapid search changes call an async reload without awaiting it, while the controller throws if a reload is already active.

## Replication implementation

Status: **Missing**, with prototype types.

Evidence:

- `EventStoreReplication` is empty.
- `ReplicatedChange.canApply` always returns `false`.
- commands/dependency vectors are not persisted by SQLite.
- no event export/import methods exist.
- no event ID or durable deduplication constraint exists.
- no buffer for unmet dependencies exists.
- protocol message classes have no codecs or handlers.
- WebSocket transport is tested only as a binary echo pipe.
- the notes runtime uses an unassigned device ID.

The current system cannot synchronize two event stores, directly or through a relay.

## Blob implementation

Status: **Prototype only**.

`BlobChunkSizing` validates exponent/overhead ranges and calculates chunk counts/padding. One source/test contradiction is visible statically: `fromCleartextLen` chooses its exponent from `overhead + 1`, not from the payload length, while the “double chunk above maximum” test expects a maximum-size chunk and two chunks for a payload one byte over 1 MiB. That expectation cannot follow from the current algorithm.

No `BlobStore` class is implemented, the public library is empty, and the store test is a blank placeholder. No application uses blob events.

## CRDT implementation

Status: **Experimental and not application-ready**.

The title LWW wrapper is integrated, but its total ordering is incomplete. The text CRDT has serialization and basic insertion/deletion tests, including duplicate examples, but it does not establish delivery-order independence. The tests apply operations to one resolver in one chosen order; they do not compare multiple replicas receiving permutations.

Concrete correctness gaps include external changes always throwing, actor counters regressing on older merges, missing dependency buffering, arrival-dependent insertion placement, and deletion idempotence that only works after the target exists.

## `isolate_sqlite` implementation

The isolate wrapper gives the application a single serialized database owner and reconstructs remote stack traces. Its typed row accessors produce useful errors.

Concrete issues:

- migration version insertion calls asynchronous `db.execute` from inside the synchronous transaction callback instead of `tx.execute`, so the version marker is outside the migration transaction;
- `open` sets `_isOpen = true` before isolate creation/database open completes and does not restore it on failure;
- production code does not enable WAL/busy timeout;
- migration table names are interpolated without identifier validation, though they are currently developer constants;
- there is no nested-transaction guard beyond the `SyncContext` flag;
- the sibling source is not what manifests directly consume.

## Test coverage assessment

Test-described coverage is strongest for:

- local command/event-store happy paths;
- optimistic concurrency in memory;
- stream pagination;
- projection routing callbacks;
- finance domain commands/projections;
- basic CRDT text operations in one resolver;
- blob sizing edge cases and libsodium constant parity;
- SQLite wrapper data types, transactions, migrations, and error propagation;
- WebSocket byte echo.

Coverage is absent or inadequate for:

- two independent peers/stores;
- event import/export and duplicate/reordered delivery;
- convergence permutations;
- device enrollment/removal;
- encrypted events or cryptographic tampering;
- blob write/read/encrypt/transfer/evict/repair;
- backup and clean restore;
- crash points and database reopen for `core`;
- multi-stream SQLite parity;
- non-empty multi-page projection replay in both stores;
- notes application behavior—the only app test asserts `2 + 2 == 4`;
- long histories, malformed input, bounds, and resource exhaustion.

## Current capability matrix

| Capability                              | Status                                               |
| --------------------------------------- | ---------------------------------------------------- |
| Local offline note editing              | Implemented prototype                                |
| Durable local event append              | Implemented for one stream                           |
| Local projection replay                 | Implemented, with noted pagination/error limitations |
| Local optimistic concurrency            | Implemented                                          |
| Multi-stream atomic command             | Memory only; SQLite missing                          |
| Deterministic concurrent merge          | Missing                                              |
| Device identity/membership              | Missing                                              |
| Event replication                       | Missing                                              |
| Event encryption/authentication         | Missing                                              |
| Blob persistence/encryption/replication | Missing                                              |
| Greedy/light retention                  | Missing                                              |
| Relay                                   | Missing                                              |
| Encrypted backup/restore                | Missing                                              |
