# Blob feature specification

This temporary specification describes future behavior. Track implementation
below and delete this document after implementation and verification are
complete.

## Intended behavior

Blobs are immutable bytes identified by strings. Production IDs are UUIDs,
allocated through `IdGenerator` before persistence.

`BlobStore` provides get/save operations keyed by string ID. Missing bytes
return null. Repeated saves of identical content succeed; conflicting content
under the same ID fails. Successful saves expose complete, durable bytes.

Durable metadata tracks command ownership and blob availability separately from
byte storage.

## Commands and persistence

- Command handlers can read blobs and register writes. Registration returns an
  ID immediately.
- `StoredCommand.blobIds` preserves registration order, independent of write
  completion order. All registered writes belong to that command.
- Locally authored commands save blob bytes before committing events. Failed
  blob writes prevent event commit.
- Events and ordered blob references commit atomically. Commands producing no
  events do not persist collected writes.
- Received commands persist events and blob references before ACK. Missing
  blobs become `pending`; existing available blobs remain `available`.
- Command ACKs never wait for blob downloads.

## Independent blob replication

- A separate replicator fetches pending blobs by ID from connected peers. Any
  peer holding the bytes can serve them.
- Attempt priority follows local command log position, then blob position
  within the command. Concurrent commands may have different local order on
  different devices.
- Failed or unavailable blobs remain pending while later blobs proceed. Retries
  must not starve later work.
- Pending work survives restart. Notifications wake workers but do not replace
  durable work tracking.
- Received bytes become durable before availability changes to `available`.
  Recovery reconciles interrupted status updates with already-saved bytes.
- Duplicate references and deliveries do not duplicate required work or reset
  availability.
- Blob replication uses no vector clocks. Existing command vectors remain part
  of event replication.
- Consumers can inspect availability separately from reading bytes. Replicated
  events may reference blobs that are still pending.

## Failures and cleanup

Failed transfers remain retryable. Partial incoming writes may be discarded
without removing pending references.

Local bytes left behind by failed or abandoned commands are cleanup candidates.
Background cleanup remains outside CQRS execution, with durable ownership and
staging information sufficient to identify candidates safely.

Cleanup coordinates with active writes and commits. Neither elapsed time nor an
exception observed by the caller proves that bytes are safe to delete. Durable
committed references protect blobs from cleanup.

Initially, retain all blobs referenced by committed history and replicate them
to every participating device. Whole-blob transfers are sufficient. Streaming,
resumable transfers, content deduplication, and deletion of committed blobs are
outside this specification.

## Implementation TODO

Check an item only when its implementation and relevant tests pass.

- [ ] Establish string IDs, immutable byte-storage behavior, and availability
  metadata contracts.
- [ ] Integrate command-context writes and ordered `StoredCommand.blobIds`,
  including persistence and serialization.
- [ ] Implement durable pending registration with received commands and recovery
  across interrupted saves and status updates.
- [ ] Implement independent blob replication, ordered attempts, retries,
  duplicate handling, and peer-to-peer forwarding.
- [ ] Establish abandoned-write tracking and the cleanup integration contract.
  Keep background cleanup outside command execution.
- [ ] Validate failure recovery and end-to-end replication using in-memory
  channels and fake transports.
- [ ] Complete root analysis and cross-workspace tests. Update concise public
  documentation where behavior changes.
- [ ] Delete this temporary specification after completion.

Validation must cover event ACKs while blobs remain pending, restart after ACK,
unavailable earlier blobs, forwarding through another actor, duplicate and
conflicting saves, command concurrency failures, and cleanup racing with active
writes. Memory and persistent stores must satisfy the same contracts.
