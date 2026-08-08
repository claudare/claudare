# Claudare Architecture

## Review scope

This document describes the code present on 2026-08-05 in `core`, `notes_app_v0`, and, where it affects the framework, `isolate_sqlite`. It is based on static source inspection only. No build, test, migration, database, or application command was executed.

The filename intentionally preserves the spelling requested in the study brief.

## Architectural verdict

The repository contains a usable prototype of a **local event-sourced/CQRS application runtime**, not yet a distributed offline-first framework.

The implemented path is:

1. accept an application command;
2. read and optimistically lock one event stream;
3. append one or more plaintext events atomically to local SQLite;
4. route the committed events to local projections;
5. rebuild projections from the event log after startup or a runtime-version change.

The distributed portions are design sketches. There is no working replication engine, event import/export API, device enrollment, recipient encryption, blob persistence/transfer service, greedy/light retention policy, relay implementation, or backup/restore path.

## Repository composition

| Folder           | Actual role                                                                                                                                            | Maturity                                                                          |
| ---------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------ | --------------------------------------------------------------------------------- |
| `core`           | Dart package containing CQRS commands, local event stores, projection runtime, experimental CRDTs, WebSocket byte transport, and early sync/blob types | Local CQRS is substantive; replication and blobs are incomplete                   |
| `notes_app_v0`   | Flutter desktop/mobile example using `core` and two SQLite databases                                                                                   | Demonstrates local persistence and replay; does not exercise distributed features |
| `isolate_sqlite` | Dart wrapper that owns a SQLite connection in a dedicated isolate and exposes synchronous callbacks through asynchronous messages                      | Small functional dependency with an important migration bug                       |

`notes_app_v0` consumes `core` through `path: ../core`. Both `notes_app_v0` and `core` consume `isolate_sqlite` from Git at ref `0.3.1`, rather than from the sibling folder. The lockfile resolves it to commit `93f5498fa82af26b5d743f2f9a1bf5b5440c9e36`. Consequently, editing the sibling `isolate_sqlite` directory does not automatically change the application dependency.

The public package surface is fragmented. `core/lib/cqrs.dart` exports the functioning CQRS API; `core/lib/core.dart` exports only counter/timestamp helpers; `core/lib/blob_store.dart` is empty; and sync types remain internal. That accurately reflects the current maturity but is not yet a coherent framework API.

## Current runtime topology

```text
Flutter UI
   |
   v
NotesRuntime / bound commands
   |
   v
CommandExecutor ---- reads stream ----+
   |                                  |
   +---- atomic append ----------> notes.db
                                     |-- event + stream tables
                                     |-- note projection table
                                     `-- runtime version table
   |
   +---- live EventEnvelope routing
           |-- NoteProjection (waited for)
           `-- SearchProjection (eventual)
                    |
                    `--------------> search.db (FTS5 + checkpoint)
```

There is no synchronization component connected to this topology.

## Local command and event flow

`NotesRuntime` constructs a `CqrsRuntime`, registers note and search projections, and binds create, update, trash, and restore commands. It passes `DeviceId.unassigned()` to the runtime (`notes_app_v0/lib/runtime/notes_runtime.dart:74`), so every installation currently writes under the same sentinel device ID.

A command obtains a `CommandStream` from its context. `lock`, `mustExist`, `mustNotExist`, or `scan` records the stream's current version. `scan` also accumulates the last causal pair seen in the stream. Appending creates an encoded event and an occurrence timestamp. `CommandExecutor` converts the accumulated work to `StreamAppends` and calls the event store.

The SQLite store executes a single-stream append in one database transaction. It checks the stored stream version against the caller's lock, allocates stream and local sequence numbers, inserts all events, and advances the stream version. This is a sound local optimistic-concurrency boundary for one stream.

Important limitations:

- SQLite multi-stream appends throw `UnimplementedError` (`event_db.dart:167`), even though the command API and finance example support them in memory.
- Commands and dependency vectors are accepted by the store API but are not persisted by SQLite (`event_db.dart:157`).
- Commands that fail, are nacked, or emit no events are passed as empty appends and immediately discarded by both stores.
- The event schema has no event ID and no uniqueness constraints for `(device_id, device_sequence)` or `(stream_id, stream_version)` beyond the separate stream-version check.
- The stored “causal sequence” is locally generated from the current device's maximum. The dependency vector is not durable, so it cannot reconstruct a replicated causal graph.

## Event representation and ordering

An application event is stored as:

- stream ID;
- per-stream version;
- kind string;
- opaque detail bytes;
- occurrence time;
- device ID;
- device-local sequence;
- causal sequence;
- database-local sequence.

The local sequence is the projection order for one database. It is useful for deterministic replay of that database, but it is not a portable global order. Different peers importing the same concurrent events could assign different local sequences.

`EventDependency` is a vector of maximum sequence per device, and `DeviceSequences` can check strictly incremental per-device delivery. Those are useful primitives, but no production path persists or enforces them during import. `ReplicatedChange.canApply` always returns `false`, and `EventStoreReplication` is empty (`event_store_replication.dart:72-81`).

There is therefore no implemented convergence rule for independently authored histories.

## Projection model

Each projection exposes a stream pattern, event codec, checkpoint, reset, and apply method. `ProjectionRuntime` can:

- reset a projection;
- replay filtered events in local-sequence order;
- queue live events through a FIFO;
- capture the first projection error through a failure handler.

`CqrsRuntime` resets all projections when its application runtime version changes, catches them up, then stores the new runtime version. A command can designate projections as “consistent”: the command waits for their queued apply callbacks after the event commit. Other projections are dispatched without waiting.

This is consistency between the command response and a local read model, not one atomic database transaction. The event commit and projection update are separate. A projection failure leaves the authoritative event durable and the projection repairable by replay, which is a reasonable event-sourcing choice, but callers need explicit degraded-state semantics.

The memory event store is not a full reference implementation: its projection query always returns `sequenceNumberCursor: null`, so replay stops after one page when history exceeds the configured page size (`memory_event_store.dart:232-245`).

## `notes_app_v0` data model

The implemented note stream is `note/*` with five event kinds:

- `note.created`;
- `note.title.updated`;
- `note.content.updated`;
- `note.trashed` (also decodes legacy `note.deleted`);
- `note.restored`.

The note projection stores one row per note in `notes.db`. Title state uses a timestamp-based last-write-wins wrapper. Content is a full string replacement. Trash/restore is arrival-order state. Search is a second, eventual projection in `search.db` using SQLite FTS5.

On startup the application opens both databases, migrates the event store, and initializes projections. If projection runtime version `7` differs from the stored version, both projections are reset and rebuilt. The loading screen then attempts to insert a fixed example note and catches every failure as “test data was not inserted.”

This gives the example genuine local offline behavior: commands do not require a network and state can be reconstructed from local events. It does not demonstrate eventual multi-device replication.

## Conflict semantics in the example

The example does not currently converge safely under concurrent peer edits:

- note content is whichever full replacement is applied last in local replay order;
- trash and restore are also local replay-order decisions;
- title chooses the greatest wall-clock timestamp, but equal timestamps choose the event applied last and have no device/event tie-breaker;
- device clocks are not synchronized or bounded;
- a title event that loses the LWW comparison can still replace `updatedAt` with its own timestamp;
- no conflict is exposed to the user.

Because imported event order is not defined, two peers can compute different states from the same concurrent event set.

## CRDT experiments

`core/lib/src/crdt` contains a timestamp LWW value and an experimental text sequence CRDT. The text implementation is not integrated into notes; the controller explicitly sends full content replacements.

The text CRDT is not ready for replication:

- applying an external change always ends by throwing `Exception('TODO')` (`crtd_text.dart:57-94`);
- insertion placement mutates a list according to arrival and does not use the supplied deterministic row comparators;
- a delete whose target has not arrived throws from `firstWhere` instead of buffering the dependency;
- the vector clock overwrites an actor's counter even when an older operation arrives (`vector_logical_clock.dart:40-44`);
- operation IDs use small integer actor IDs with no connection to enrolled device identities.

## Blob subsystem

The blob subsystem is a collection of primitives, not a store:

- `BlobId` creates an 11-character Base58 ID from 64 random bits;
- `BlobChunkSizing` describes fixed 4 KiB–1 MiB ciphertext chunks;
- constants match libsodium secretstream XChaCha20-Poly1305 sizes;
- `BlobCreatedSodiumSecretstream`, `BlobReady`, and `BlobTombstoned` model lifecycle events;
- `StoredBlob` is only a transport/storage-shaped value;
- the public `blob_store.dart` exports nothing;
- the blob-store test contains an empty placeholder.

There is no file/chunk repository, encryption/decryption pipeline, header storage, authenticated metadata, transfer protocol, possession inventory, greedy/light policy, eviction, garbage collection, or restore implementation. `BlobCreatedSodiumSecretstream` embeds the raw 32-byte key in its JSON representation as Base64; its safety therefore depends entirely on event-store encryption that does not yet exist.

## Transport and synchronization sketches

The WebSocket layer transports arbitrary binary messages and has one loopback end-to-end test. The server accepts any WebSocket upgrade, does not authenticate peers, and returns a plain `ws` URI. No protocol codec connects the WebSocket to event or blob storage.

The event protocol file declares proposed relay/direct message shapes, including ciphertext, public keys, a proof placeholder, sequence acknowledgements, and a direct cleartext payload. These classes have no serialization, authentication, state machine, retry integration, or handlers. The server described in the product goal is not present.

## `isolate_sqlite` boundary

`IsolateSqlite` owns a `sqlite3` database in a dedicated Dart isolate. Calls send a synchronous callback to that isolate and return its result or reconstructed error/stack trace. `transaction` wraps the callback in `BEGIN`, `COMMIT`, and `ROLLBACK`. Since callbacks themselves are synchronous, database operations handled by one isolate form a useful serialization boundary.

The migration helper violates that boundary: while inside the transaction callback it records an applied migration with `db.execute(...)` instead of `tx.execute(...)` (`sqlite_migration.dart:50`). That returns an unawaited future and queues work outside the current transaction. Schema changes can commit without their version marker, making crash recovery and reapplication unsafe.

The application also never supplies `IsolateSqlite.enableOptimizations`, so WAL and the helper's busy timeout are not enabled by the shown production factory.

## Intended architecture versus current evidence

| Product goal                             | Current source evidence                                        |
| ---------------------------------------- | -------------------------------------------------------------- |
| Fully offline application operation      | Implemented for local note CRUD and replay                     |
| Eventual synchronization between devices | Not implemented                                                |
| No required central server               | Locally true because there is no sync; peer protocol absent    |
| Multi-hop event/blob exchange            | Not implemented                                                |
| Recipient-specific event encryption      | Message field sketches only                                    |
| Shared-key encrypted blobs               | Event and sizing primitives only; no encryption pipeline/store |
| Greedy and light peers                   | Not implemented                                                |
| Queue-and-forward central relay          | Not implemented                                                |
| Encrypted third-party backup peer        | Not implemented                                                |
| Deterministic convergence                | Not established; current note merges can diverge               |
