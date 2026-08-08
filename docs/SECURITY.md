# Claudare Security Review

## Scope and conclusion

This is a static review of the current source, not a cryptographic audit. No code was executed.

The present repository is **not secure as a distributed system** because the distributed security system does not exist yet. The local notes prototype stores plaintext application events and projections. Event encryption, peer authentication, key establishment, membership, replay protection, relay authorization, blob encryption, and encrypted backup/restore are absent or represented only by data-shape sketches.

This is consistent with the developer's statement that security is incomplete, but it means no current code should be deployed under the proposed untrusted-relay or untrusted-backup threat model.

## Existing positive foundations

- Production note IDs use 128 random bits from `Random.secure()` through `RandomIdGenerator`.
- Event detail is stored as bytes rather than tied to one object serializer.
- Local single-stream event appends use a SQLite transaction and optimistic stream-version check.
- The proposed blob primitive names an authenticated streaming construction, libsodium secretstream XChaCha20-Poly1305.
- WebSocket code rejects non-binary frames.
- SQLite query parameters are used in most repositories.
- Event codecs wrap ordinary decode/encode exceptions with context.

These are implementation building blocks, not an end-to-end security boundary.

## Critical missing controls

### No device identity or enrollment

`DeviceId` is only a 16-bit integer wrapper. The notes runtime always uses `DeviceId.unassigned()` (`notes_runtime.dart:74`). There is no device keypair, owner/root identity, enrollment ceremony, verification code, membership log, revocation, recovery, or association between a device number and a cryptographic identity.

Without authenticated enrollment, recipient-specific encryption cannot prevent a relay or malicious peer from substituting its own public key.

### No event cryptography

No source path encrypts, decrypts, signs, authenticates, hashes, or verifies events. `SyncEventMessageMain` and relay message types merely contain a `ciphertext` field. There is no algorithm selection, versioned envelope, nonce generation, associated data, sender authentication, session state, key rotation, or serialization.

The “Signal-like” goal therefore has zero inherited Signal security properties. A safe design should use a reviewed protocol or library and state exactly which properties—pairwise authentication, forward secrecy, post-compromise recovery, asynchronous prekeys, group membership—are required.

### No authenticated replicated event identity

The event table has a database-local primary key but no stable event ID, author signature/MAC, content commitment, or unique `(device_id, device_sequence)` constraint. Dependencies are not persisted. There is no import verifier or replay/deduplication path.

An untrusted transport could not yet be prevented from forging, duplicating, reordering, truncating, or rolling back event history.

### No secure blob implementation

Blob lifecycle events and secretstream constants exist, but encryption is not performed. `BlobCreatedSodiumSecretstream.toJson` serializes the raw key as Base64 (`blob_created.dart:9,36`). Today such an event would be stored as plaintext if wired into the current event store.

There is no key hierarchy, wrapping key, epoch, rotation, nonce/header storage, associated data, chunk integrity protocol, or secure deletion story. A single shared blob key without rotation would let a removed or compromised device retain indefinite access.

### No backup security or restore verification

There is no backup peer implementation, separate backup unlock key, completeness manifest, authenticated checkpoint, rollback detection, or clean-device restore workflow. Encrypted retention alone would not prove that a backup is complete or current.

## Local confidentiality

`notes.db` stores event kinds and plaintext JSON detail blobs. The note projection stores plaintext title/content and timestamps. `search.db` stores plaintext title/content in FTS5. Neither database is encrypted by the application, and no OS key-store or user-unlock mechanism is present.

This means local database theft, filesystem backups, crash collection, or another process with file access exposes note contents. Even after event transport encryption is added, the local-at-rest threat model must be decided explicitly.

Application logging also prints note titles/content from command handlers and emits database/projection errors with string interpolation. Production diagnostics must not contain plaintext content or secrets.

## Transport exposure

`ServerTransportWebsocket` binds a plain HTTP server and upgrades any WebSocket request. It does not enforce the requested URI path, authenticate the client, authorize an application/device, limit frames, rate-limit peers, or establish TLS. The client accepts both `ws` and `wss`.

This transport is currently only a byte pipe and is not connected to replication, but it must be treated as untrusted. Message-layer authenticated encryption is still required even when TLS is used, because relays and intermediate peers are outside the plaintext trust boundary.

## Input validation and denial of service

- Sync message classes have no decoder or size limits.
- Event detail size, event batch size, dependency-vector size, blob length, and peer queues are unbounded in the current model.
- `DeviceId.fromBytes` does not check input length and uses the assertion-only constructor.
- Several security-relevant range checks use `assert`, which disappears in production Dart builds.
- `BlobId(String)` accepts arbitrary values; random blob IDs contain only 64 bits.
- Unknown event kinds cause projection failure rather than quarantine/forward-compatible retention.
- Text CRDT deletes throw when their target is missing, making reordering an availability attack if exposed to peers.

Every network decoder needs hard limits before allocation and before persistence. Invalid data should be rejected or quarantined without halting unrelated projection progress.

## SQL construction issue

`event_db.dart:316-325` interpolates `PatternFilter` strings directly into SQL. The exact form omits SQL string quoting (`stream_id = $value`), so it is functionally broken for normal text. The prefix form embeds the value in a quoted `LIKE` expression without escaping quotes, `%`, or `_`.

Current note projection patterns are developer-defined constants, which reduces immediate exposure, but `PatternFilter` is a framework abstraction. It must return SQL plus bound parameters, and wildcard semantics must be escaped deliberately.

## Clock and conflict security

Title conflict resolution trusts device wall-clock `DateTime`. A malicious or badly skewed peer can write a far-future timestamp and dominate later values. Equal timestamps use arrival order because the LWW value has no stable tie-breaker. Content and trash state are entirely arrival-order based.

Conflict ordering must be derived from authenticated logical metadata, or the domain must use a convergent operation type. Wall time may remain display metadata but should not be the sole authority for replicated state.

## Metadata privacy

The proposed relay message exposes sender and receiver public keys, message sequence, and ciphertext length. `StoredBlob` exposes tenant, application, device, sequence, timestamp, and rounded ciphertext length. No padding schedule, key rotation strategy, mailbox unlinkability, or traffic-analysis policy exists.

The eventual protocol should document exactly which metadata each direct peer, relay, intermediate peer, and backup host can observe. Content encryption must not be described as anonymous or metadata-private.

## Required security architecture

Before network replication is enabled, define and review:

1. A root-of-trust and device enrollment/recovery ceremony.
2. Authenticated device membership events with removal and rotation semantics.
3. A versioned canonical event envelope with stable ID, author, recipient, sequence, dependencies, payload commitment, and authenticated associated data.
4. A reviewed recipient encryption/session protocol with replay protection and explicit forward-secrecy guarantees.
5. Durable monotonic per-device sequence allocation that survives crashes and rejects reuse.
6. A blob key hierarchy using random per-blob content keys wrapped by membership epochs, rather than one immortal raw shared key.
7. Authenticated secretstream headers/chunk indexes/blob metadata and verified resumable transfer.
8. Hard parser, storage, bandwidth, retry, and queue limits.
9. An authenticated history/checkpoint scheme that detects truncation, forks, and rollback.
10. A backup manifest and restore protocol tested from a clean device with only documented recovery material.
11. Local key custody and at-rest encryption policy.
12. Independent cryptographic review and adversarial protocol testing.

## Security severity summary

| Severity | Finding | Current impact |
| --- | --- | --- |
| Critical | Device enrollment and authenticated identity absent | Secure peer/relay use cannot be implemented safely on current identity model |
| Critical | Event encryption/authentication/import verification absent | Proposed distributed confidentiality and integrity are not provided |
| Critical | Blob encryption/store/key lifecycle absent | Proposed blob and backup confidentiality are not provided |
| High | Plaintext local event, projection, and search databases | Local files reveal all note content |
| High | No stable authenticated event identity or durable dependencies | Deduplication, replay defense, and convergence cannot be enforced |
| High | Wall-clock/arrival-order conflict resolution | Skewed or malicious peers can cause divergent or dominating state |
| Medium | WebSocket transport has no auth, TLS enforcement, limits, or path enforcement | Unsafe if connected directly to replication |
| Medium | Framework projection SQL is interpolated | Exact filters fail; non-constant input could alter SQL semantics |
| Medium | Assertion-only and incomplete boundary validation | Malformed remote data could crash or corrupt protocol state |

