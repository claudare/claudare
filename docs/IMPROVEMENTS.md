# Source-backed improvements

## How to use this roadmap

This is an ordered roadmap for the reusable core. The notes app is a prototype
consumer that helps expose missing core contracts; its domain behavior does not
set the architecture for future applications. Do not start transport,
encryption, or backup work before persistence and replicated-data contracts are
decided.

For conventions governing implementation work, see
[CONVENTIONS.md](../CONVENTIONS.md).

## P0 - protect local correctness

### Make migrations atomic

`SqliteMigrations.migrate` applies schema work through `tx`, but writes the
migration marker through `db.execute`. Record the marker with `tx.execute`,
validate unique/increasing migration versions, and add reopen/interruption
tests. A migration must be all applied or safely retried.

### Harden event filters

Event database filters use bound values. Define explicit `LIKE` escaping and
add quotes, `%`, `_`, Unicode, and exact/prefix edge-case tests.

### Make projection lifecycle explicit

Give the runtime lifecycle states and queue barriers for initialize, rebuild,
ready, degraded, and shutdown. Prevent resets from racing command projection
work, expose eventual-projection health/lag, and provide a graceful close path
for runtime queues and both SQLite isolates.

## P1 - strengthen reusable core behavior

### Make projection progress durable

Require every consumed event, including intentional no-ops, to advance a
projection checkpoint atomically with the projection's derived-state change.
Provide reusable guidance or helpers for projection transaction ownership and
test restart behavior at each checkpoint boundary.

### Define supported public APIs

Document stable public libraries and extension points for commands, event
codecs, event stores, projections, runtime repositories, IDs, time, CRDT
helpers, logging, and SQLite. Keep application consumers out of package `src`
internals.

### Separate local and replicated concepts

Keep event local sequence, command local sequence, and stream version separate
from `CommandId`, indexed `EventId`, and `VersionVector`. The flat persistence
model and separate command/event staging are implemented, but do not constitute
a complete replication protocol without transport, identity, scheduling, and
resource-bound contracts.

### Use prototype feedback correctly

Use `apps/notes` to test whether core contracts are usable. Fix prototype
issues when they reveal a missing reusable contract. Keep purely note-specific
UI behavior in the app unless another application needs the same abstraction.

## P2 - prerequisites for multi-device work

### Specify the replicated change model

Before implementing network code, define canonical versioned command/event
bytes, authenticated device identity and database-local integer translation,
bounded orphan and pending scheduling, range exchange, and resumable
import/export. Preserve idempotent `CommandId` and `EventId` handling and keep
receiver-local order separate from replicated identity.

### Define convergent note semantics

Choose deterministic semantics for title, content, trash/restore, timestamps,
and concurrent creation. A timestamp-only LWW title and arrival-order whole
content replacement are not sufficient. Add multi-replica permutation,
duplicate, partition, and restart tests before adopting a transport.

### Build security from a reviewed design

Add device enrollment, authenticated membership and removal, recovery, key
rotation, replay-safe authenticated envelopes, local key custody, resource
limits, and encrypted backup/restore only after a documented threat model and
cryptographic review. Do not infer security from sequence fields or a future
network channel.

## Completion evidence

For each item, include focused tests, root analysis, and the relevant package
tests. For future replication/security work, require independent SQLite stores,
delivery permutations, crash/restart coverage, malformed-input limits, and a
clean-device restore test before declaring a capability complete.
