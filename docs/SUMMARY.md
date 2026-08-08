# Claudare Study Summary

## Bottom line

Claudare currently implements a promising **local event-sourced CQRS prototype**. The notes application can create and edit notes without a network, durably append local events, maintain SQLite read models, and rebuild projections from history.

It does **not yet implement the distributed framework described in the project goal**. Replication, convergence, authenticated device identity, event encryption, blob storage/transfer, relay processing, greedy/light retention, and encrypted backup/restore are absent or limited to sketches and value types.

This conclusion comes from static source inspection only. No code or tests were executed.

## What works today

- A command API with stream reads, existence checks, and optimistic locks.
- Atomic single-stream event appends in SQLite.
- Memory and SQLite event stores for local use.
- Event codecs with contextual error wrapping.
- Live projection routing and startup replay from checkpoints.
- Runtime-version-driven projection rebuilds.
- A note projection in `notes.db` and eventual FTS5 search projection in `search.db`.
- Local create, title/content edit, trash, restore, reset, and replay workflows.
- A serialized SQLite owner running in a dedicated Dart isolate.
- A binary WebSocket transport prototype and early CRDT/blob experiments.

## What does not work yet

- Two devices cannot exchange or import events.
- `EventStoreReplication` has no methods and `ReplicatedChange.canApply` always returns `false`.
- The notes app uses the same unassigned device sentinel on every installation.
- SQLite discards commands and causal dependency vectors needed by the proposed change-based sync boundary.
- Events have no stable authenticated ID or durable deduplication constraint.
- Concurrent note state is not deterministically convergent.
- No source path encrypts or authenticates events.
- Blob code has no store, encryption pipeline, transfer, retention, or repair implementation.
- The relay and backup peer do not exist.
- No multi-peer, convergence, crypto, blob, or restore tests exist.

## Most important concrete defects

1. **Migration markers are not atomic.** `isolate_sqlite` calls asynchronous `db.execute` inside a migration transaction callback instead of `tx.execute`, allowing schema changes and version records to separate.
2. **Production SQLite lacks multi-stream appends.** It throws `UnimplementedError`, although the public model and memory-backed finance example support them.
3. **Command/dependency history is discarded.** SQLite ignores `StoredCommandWrite` and `EventDependency`; failed/no-op commands are also discarded by memory.
4. **Projection SQL filtering is malformed and interpolated.** Exact text lacks quoting and prefix patterns are not safely escaped/bound.
5. **Memory projection replay stops after one page.** The memory store always returns a null continuation cursor.
6. **Most safe-store error wrapping misses async failures.** Methods return futures from synchronous `try` blocks without awaiting them.
7. **Note conflict rules can diverge.** Content and trash use arrival order; title LWW uses untrusted wall time and has no deterministic tie-breaker.
8. **The text CRDT is unfinished.** External changes always throw, missing dependencies are not buffered, vector clocks can regress, and insertion can depend on delivery order.
9. **Final UI saves race navigation/disposal.** The note screen flushes after a route pop instead of blocking navigation until local durability is established.
10. **The sibling SQLite package is not wired as a sibling dependency.** Both consumers use Git ref `0.3.1`, so local folder changes are not automatically exercised.

## Security conclusion

The current system should be considered plaintext and locally trusted:

- note events and read models are plaintext SQLite data;
- search contains plaintext title/content;
- no device keys, enrollment, membership, revocation, or recovery exist;
- sync “ciphertext” fields have no cryptographic implementation;
- WebSocket transport has no peer authentication, message limits, or server TLS enforcement;
- blob creation events serialize a raw key as Base64 even though event-store encryption is absent;
- no history commitment detects replay, truncation, forks, or rollback.

The proposed Signal-like layer must be specified and independently reviewed; naming ciphertext and public-key fields does not supply Signal's security properties.

## Architectural judgment

The project has chosen several useful foundations:

- local events are authoritative;
- read models are disposable and replayable;
- local sequence and replicated/device sequence are conceptually separate;
- command dependencies are modeled as a vector;
- event and blob planes are recognized as different problems;
- SQLite transactions provide a natural local atomicity boundary.

The next architectural step should not be another transport. It should be a precise replicated-change specification and a deterministic multi-peer simulator. Until the event identity, dependency, import, conflict, membership, and cryptographic invariants are fixed, transport and relay work would only move ambiguous state faster.

## Priority roadmap

### P0 — prerequisites for any distributed use

1. Specify a canonical authenticated event/change envelope.
2. Persist commands/change boundaries and dependency vectors.
3. Implement stable IDs, durable deduplication, per-device sequence constraints, import buffering, and idempotent export/import.
4. Define deterministic conflict semantics for every note field.
5. Implement authenticated device enrollment, membership, removal, recovery, and key rotation.
6. Select/review the event encryption protocol.
7. Implement a per-blob key hierarchy and real encrypted blob store.
8. Prove convergence and replay resistance using independent stores.

### P1 — local correctness and operational resilience

1. Fix migration atomicity and event-filter SQL.
2. Add SQLite multi-stream transactions and store parity tests.
3. Fix memory projection pagination and async error translation.
4. Coordinate runtime initialization/rebuild with command and queue lifecycle.
5. Make projection checkpoints advance for intentional no-ops.
6. Add bounded sync queues, inventory exchange, backpressure, repair, and resumable blob transfer.

### P2 — application and evolution quality

1. Make navigation wait for final local save.
2. Remove automatic example-note insertion and make startup idempotent.
3. Preserve search rank and make filter/order semantics consistent.
4. Close database isolates and runtime queues cleanly.
5. Version event, crypto, transport, and projection semantics independently.
6. Consolidate supported public package APIs.

## Documentation map

- [ARCHETECTURE.md](ARCHETECTURE.md) describes the implemented structure and contrasts it with the intended distributed topology.
- [SECURITY.md](SECURITY.md) records current security evidence, trust-boundary failures, and required controls.
- [IMPLEMENTATION.md](IMPLEMENTATION.md) traces the local runtime, event store, projections, notes app, SQLite wrapper, tests, and feature maturity.
- [IMPROVEMENTS.md](IMPROVEMENTS.md) ranks source-backed defects and missing framework capabilities with concrete completion evidence.
- [SUMMARY.md](SUMMARY.md) is this executive synthesis.

## Final capability assessment

| Goal                          | Assessment                                 |
| ----------------------------- | ------------------------------------------ |
| Single-user local application | Prototype achieved                         |
| Offline local operation       | Achieved for implemented note workflows    |
| Event-sourced local state     | Achieved for single-stream SQLite commands |
| Eventually consistent devices | Not achieved                               |
| Serverless peer exchange      | Not achieved                               |
| Multi-hop sync                | Not achieved                               |
| Recipient-encrypted events    | Not achieved                               |
| Shared-key encrypted blobs    | Not achieved                               |
| Greedy/light peers            | Not achieved                               |
| Untrusted central relay       | Not achieved                               |
| Untrusted encrypted backup    | Not achieved                               |
| Production security           | Not achieved                               |
