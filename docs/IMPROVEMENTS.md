# Source-Backed Shortcomings and Needed Improvements

## Purpose

This document is derived from the current source. It separates defects in implemented local behavior from missing capabilities required by the stated distributed/offline-first goal. Priorities assume the goal is a trustworthy eventually consistent framework, not merely a local notes application.

## P0: Define and implement the replicated data model

### 1. Establish a canonical replicated event envelope

Current shortcoming: events have no stable global identity, the SQLite schema does not persist command boundaries or dependency vectors, and no import/export API exists. The `ReplicatedChange` model cannot apply anything.

Needed improvement:

- specify canonical bytes and a protocol version;
- assign a stable event ID derived from author/device and monotonic sequence or a collision-resistant random ID;
- include author identity, per-device sequence, command/change ID, dependencies, stream ID, event kind/version, and payload;
- authenticate all invariant metadata as associated data or signed content;
- add durable uniqueness constraints for event ID and author sequence;
- implement atomic import of a complete change, durable buffering for missing dependencies, idempotent duplicate handling, and export by peer inventory;
- keep database-local projection sequence separate from replicated identity/order.

Completion evidence must include two independent SQLite stores converging after duplicated, reordered, delayed, and interrupted exchange.

### 2. Choose deterministic domain conflict semantics

Current shortcoming: content and trash/restore use arrival order; title LWW lacks a stable tie-breaker and trusts wall clocks. Same event sets can produce different peer state.

Needed improvement:

- define a total, authenticated tie-breaker for scalar LWW values, such as hybrid/logical clock plus stable author/event ID;
- decide whether note content is a text CRDT, versioned whole-document register with visible conflicts, or another domain operation model;
- define delete/trash versus edit/restore semantics explicitly;
- make `createdAt` and `updatedAt` derived deterministically;
- add convergence property tests that apply the same accepted events in all relevant orders;
- surface unresolved conflicts in application state rather than silently dropping intent.

Do not integrate the current text CRDT until external changes, missing dependencies, deterministic insertion order, monotonic vector merges, snapshots, and replica-permutation tests are complete.

### 3. Implement real device membership

Current shortcoming: all note installations use one sentinel device ID, and an integer device ID has no authenticated owner.

Needed improvement:

- create an owner/root trust key and device identity keypairs;
- implement authenticated enrollment, displayable verification, device listing, removal, and recovery;
- allocate device protocol identifiers without relying on assertion-only 16-bit values;
- persist membership as an ordered authenticated state machine;
- specify which history a newly enrolled device may receive;
- rotate future encryption epochs after removal or compromise.

## P0: Build the security protocol before enabling sync

### 4. Replace ciphertext-shaped classes with a reviewed protocol

Current shortcoming: sync classes only name fields; there are no codecs, keys, sessions, authentication, replay checks, or handlers.

Needed improvement:

- document the threat model per direct peer, relay, intermediate peer, and backup;
- select a reviewed asynchronous pairwise or group protocol instead of inventing “Signal-like” behavior piecemeal;
- version envelopes and bind recipient, sender, event identity, sequence, dependencies, and application context;
- ensure crash-safe nonce/session state;
- reject replay and equivocation before domain application;
- separate transport acknowledgement from authenticated durable import acknowledgement;
- design multi-hop forwarding so intermediaries cannot forge origin or completion claims.

### 5. Implement a blob key hierarchy and store

Current shortcoming: raw blob keys are serializable event fields; no blob bytes are encrypted or stored.

Needed improvement:

- generate at least 128-bit blob IDs or content commitments and validate their representation;
- generate an independent random content key per blob;
- wrap content keys under membership/backup epochs rather than expose one permanent shared key;
- implement secretstream initialization, header storage, authenticated chunk indexes/metadata, final-tag verification, and resumable transfer;
- implement a repository for partial and complete ciphertext;
- separate logical reference, local possession, remote advertisement, pinning, and verified availability;
- implement greedy/light policies, eviction, repair, last-copy protection, tombstones, and garbage collection;
- test key rotation and clean restore.

### 6. Design verifiable encrypted backup

Current shortcoming: no backup code exists.

Needed improvement:

- define a separate backup decryption/wrapping authority;
- produce authenticated inventory/checkpoint manifests;
- detect missing, stale, forked, or rolled-back history;
- periodically verify completeness from an authorized client;
- document deletion/retention policy;
- test full recovery onto a clean device using only declared recovery material.

## P1: Repair local persistence correctness

### 7. Persist command/change boundaries and dependencies

Current shortcoming: `StoredCommandWrite`, command results, and `EventDependency` are discarded by SQLite; failed commands are discarded by both stores. Yet replication design treats a command/change as the atomic sync boundary.

Needed improvement:

- add a durable change/command table;
- atomically store command metadata, result, dependency vector, event range, author sequence, and stream locks;
- decide whether failed/nacked commands are audit records or should be removed from the replication model entirely;
- use one representation in memory and SQLite;
- make event-to-change membership immutable and queryable.

### 8. Implement SQLite multi-stream appends

Current shortcoming: the public command model supports multiple locked streams and the finance example relies on it, but production SQLite throws.

Needed improvement:

- validate all stream locks inside one transaction;
- allocate versions independently per stream;
- append all events and the containing change atomically;
- add SQLite parity tests for transfer-like commands and rollback on any conflict.

### 9. Fix migrations

Current shortcoming: `SqliteMigrations.migrate` records versions through unawaited `db.execute` from inside its transaction callback.

Needed improvement:

- use `tx.execute` for the migration marker;
- validate strictly increasing unique migration versions before opening a transaction;
- test process interruption between schema statements and marker insertion;
- test reopen/retry and partially initialized databases;
- wire the sibling package by path/workspace during development so the code under review is the code under test.

### 10. Fix event filtering and enforce schema constraints

Current shortcoming: `patternToSQL` interpolates exact/prefix values; exact text is not quoted and prefix wildcards are not escaped.

Needed improvement:

- return an SQL fragment plus bound values;
- escape `LIKE` metacharacters with an explicit escape character;
- add tests for exact, prefix, quotes, `%`, `_`, Unicode, and malicious strings;
- add unique indexes for replicated identity, author sequence, and stream version;
- add appropriate checks for positive sequences and valid device/application IDs.

### 11. Restore store parity and reliable error translation

Current shortcoming: memory projection replay ends after one page, while memory supports multi-stream operations missing in SQLite. Most `EventStoreSafe` methods fail to await, so async errors are not wrapped.

Needed improvement:

- define one behavioral contract suite for every store implementation;
- return the correct projection cursor from memory;
- await every safe-adapter operation before translating errors;
- remove assertion-only contract enforcement from production paths;
- test empty/no-op commands consistently.

## P1: Make projections operationally robust

### 12. Coordinate lifecycle and projection queues

Current shortcoming: reset can race an in-flight queue item; commands can conceptually arrive during reset/catch-up; eventual work cannot be drained or observed.

Needed improvement:

- give runtime explicit states: created, initializing, ready, rebuilding, degraded, closing;
- reject or queue commands outside ready state;
- add queue drain/barrier and graceful shutdown;
- prevent reset until in-flight work reaches a barrier, or replace the generation atomically;
- persist/report projection health and lag;
- verify all projection failure handlers before committing a new runtime version;
- quarantine unsupported events while preserving them for a future runtime.

### 13. Improve checkpoint semantics

Current shortcoming: search no-op events do not advance its checkpoint, so they replay repeatedly. Projection checkpoint ownership varies by repository.

Needed improvement:

- require every consumed event, including intentional no-ops, to advance a projection checkpoint atomically;
- provide a common SQLite projection transaction helper;
- distinguish “unsupported,” “ignored by design,” and “applied” outcomes;
- test crash/restart immediately before and after checkpoint updates.

## P1: Make blobs and replication resource-bounded

### 14. Add flow control, inventory, and repair

Current shortcoming: the model has acknowledgements and sequences but no state machine, bounds, or recovery.

Needed improvement:

- exchange compact inventories/checkpoints before payloads;
- bound message, batch, dependency vector, queue, and blob chunk sizes;
- separate event priority from bulk blob traffic;
- implement resumable transfer and backpressure;
- make retries persistent and classify permanent versus transient failures;
- use jittered backoff;
- support repair after relay loss instead of assuming messages are never dropped.

## P2: Improve application correctness and usability

### 15. Make final note saves durable before navigation

Current shortcoming: `PopScope` flushes after the route has popped, and dispose does not await pending work.

Needed improvement:

- intercept the back action before pop when there are dirty edits;
- serialize overlapping focus-loss/save operations rather than silently ignoring calls while `_flushing`;
- preserve dirty state and retry errors;
- separate “saved locally,” “replicated,” and “backed up” status.

### 16. Repair search/read-model semantics

Current shortcoming: FTS rank is lost by the subsequent unordered `IN` query; requested ordering and favorite filtering are inconsistent.

Needed improvement:

- preserve FTS ID order explicitly or join databases through a defined ranking merge;
- define how rank interacts with requested date order;
- make category semantics identical for empty and non-empty search;
- debounce/cancel stale queries rather than throwing “Already loading”;
- advance checkpoints for no-op events.

### 17. Remove startup side effects and add lifecycle ownership

Current shortcoming: `didChangeDependencies` can repeat initialization, startup inserts a fixed test note, catches all errors, and databases are never closed.

Needed improvement:

- make initialization single-flight and idempotent;
- move seed/demo data behind an explicit development action;
- catch only the expected “already exists” outcome;
- set fatal handlers before projection initialization;
- close runtime queues and both database isolates on application shutdown.

## P2: Make evolution explicit

### 18. Version replicated semantics independently

Current shortcoming: events are kind strings plus unversioned JSON, with one manual legacy alias; runtime version forces whole-projection rebuild but does not negotiate offline peers.

Needed improvement:

- version event schema, canonical encoding, crypto envelope, transport, and projection runtime independently;
- retain/upcast old event semantics deterministically;
- define a minimum supported peer protocol and mixed-version behavior;
- quarantine unknown future events without data loss;
- test a long-offline old peer rejoining after membership and schema changes.

### 19. Consolidate the framework API

Current shortcoming: `core.dart` exposes little, `cqrs.dart` is the real API, blob exports are empty, and internal prototypes are reachable mainly through source imports.

Needed improvement:

- define supported libraries for CQRS, replication, blobs, crypto, and testing;
- keep implementation internals under `src`;
- document stability and extension points;
- use `notes_app_v0` only through supported public APIs;
- make the example a compatibility test rather than a privileged sibling consumer.

## Required validation program

The existing unit tests should be extended with:

- a shared behavior suite for memory and SQLite stores;
- two- and three-peer randomized simulations;
- delivery permutation, duplication, partition, and restart property tests;
- process-crash tests around every durable transition;
- mixed-version event/protocol tests;
- malformed and resource-exhaustion inputs;
- cryptographic known-answer, tamper, replay, nonce, enrollment, rotation, and removal tests;
- blob partial-transfer, corruption, eviction, repair, and last-copy tests;
- full encrypted backup restore drills;
- real notes app tests for startup, edit, final save, replay, search order, conflict, and recovery.

## Recommended sequence

1. Freeze new transport work and write the replicated event/change specification.
2. Fix the local persistence defects: migrations, filters, parity, constraints, command/dependency durability, and multi-stream transactions.
3. Build a deterministic multi-peer simulator and prove convergence with plaintext test envelopes.
4. Implement authenticated device membership and commission cryptographic review.
5. Add versioned encrypted event envelopes and replay-safe import/export.
6. Implement blob storage, key hierarchy, transfer, retention, and repair.
7. Implement relay and greedy backup as untrusted peers against the same protocol.
8. Prove clean restore, mixed-version behavior, bounded resource use, and usable conflict/status UX.
