# Blob feature specification

This temporary specification describes future behavior. Track implementation
below and delete this document after implementation and verification are
complete.

## Intended behavior

Blobs are immutable bytes identified by random string ids. Production IDs are
UUIDs, allocated through `IdGenerator` before persistence.

`BlobStore` provides get/save operations keyed by string ID. Missing bytes
return null. Repeated saves of identical content succeed; conflicting content
under the same ID fails. Successful saves expose complete, durable bytes.

Durable metadata tracks command ownership and blob availability separately from
byte storage.

In the event store, the metadata is stored as the following:

```sql
  CREATE TABLE blob(
    log_position INTEGER PRIMARY KEY NOT NULL CHECK(log_position >= 0),
    blob_id TEXT UNIQUE NOT NULL,
    id_actor TEXT NOT NULL,
    id_sequence INTEGER NOT NULL,
    blob_index INTEGER NOT NULL CHECK(blob_index >= 0),
    available INTEGER NOT NULL,
    UNIQUE(id_actor, id_sequence, blob_index)
  );
```

The blobs are added only though running commands. The ID of each written blob
will be a random value (uuidv4 in prod). Therefore, all commands will write
unique blobs. The blobs are saved before the `CommandChanges` is commited to the
`EventStore`.

When command that emits some blobs is saved, its `id_actor` and `id_sequence` is
the same as that of the command. The `blob_index` provides an order to the
blobs, similarly to how events are ordered.

A blob ID belongs to one command and one `blob_index`. Reusing an ID in another
command or at another index is rejected. Receiving the same command again does
not reset blob availability.

Blob positions follow the same rules as command and event positions. Each log
has its own local, zero-based `log_position` sequence. Positions are assigned
in insertion order without holes; failed transactions do not consume positions.
Replication requests blobs with `available` = 0 in ascending `log_position`
order.

`getPendingBlobIds` follows the same pagination rules as `getLogEvents`. Start
with cursor 0. The cursor is a non-negative, inclusive `log_position`, so a
page contains pending IDs at positions greater than or equal to the cursor.
The `EventStore` owns the page size. For a non-empty page, `next` is the last
returned blob's `log_position` plus one. An empty page returns `next: null`,
ending the scan. Availability changes do not change positions or cursors.
Restarting replication or retrying earlier pending blobs starts a new scan at
cursor 0.

Locally saved command changes mark the blob as `available`, as it is present in
the local storage.

No cleanup of interrupted command execution is implemented. It is okay for
partially written blobs to be present in the `BlobStore` to be missing from the
`blob` table in the `EventStore`. Cleanup is a non-goal and should not be
implemented.

During replication, when `StoredCommand` is recieved, the blobs are saved as
`available` = 0, if they are not already present in the `EventStore`. `blobId`
is used as a decider. No hashing or other consistency functionality is needed.
If the `blobId` is marked as `available`, it is assumed that content is already
there.

Blob replication uses a pull model. This device requests pending blobs from a
peer by `blobId`, one at a time in `log_position` order. After downloading a
blob, it saves the bytes in the `BlobStore`, calls `markBlobAvailable` in the
`EventStore`, and proceeds to the next ID. Blob replication uses no vector
clocks, just `blobId`s.

A peer explicitly responds when it does not have the requested blob. Requests
have a finite timeout. A missing-blob response, timeout, or transfer failure
leaves the blob pending and allows the next ID in the scan to proceed. After
the scan completes, remaining pending blobs are retried from cursor 0 after a
retry delay. An unavailable earlier blob must not block later downloads.

If execution stops after saving bytes but before marking the blob available,
the metadata remains pending. Redownloading and saving the same bytes on retry
is acceptable for now; checking local bytes before downloading is not required.

The command replication ACKs never wait for blob downloads. Blob is its own
protocol operating in parallel. The replicated events may reference blobs that
are still pending. Its the application's job to handle this discrepancy.

Blobs are implemented in an "all or onthing manner". There will be no streaming,
chunked APIs, or resumable transfers. The whole blob must be in memory to be
written or read. We are currently not handling huge blobs!


## Implementation TODO

Check an item only when its implementation and relevant tests pass.

- [x] Implement blob metadata persistence, availability, and pending pagination.
- [ ] Implement more TODO's for replication.
- [ ] Delete this temporary specification after completion.
