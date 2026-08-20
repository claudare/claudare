# Application architecture

## Purpose

Applications in `apps/*` own product behavior and compose the reusable core.
They turn UI actions into domain commands, choose core persistence and read-model
implementations, and render projections. An application may depend on shared
packages; shared packages must not depend on applications.

This document describes the general application flow. Domain-specific screens,
event kinds, tables, and product features belong in their owning application.

## Current composition flow

```text
UI
  -> application composition root
      -> CqrsRuntime
          -> event store
          -> applied-change signal
          -> durable event pump
          -> asynchronous read models
```

At startup, the composition root creates the event store, runtime store,
projections, read models, logger, ID generator, time provider, and
database owners. It registers one codec per concrete event type with the CQRS
runtime, then opens storage, applies migrations, and initializes the runtime
before exposing interactive UI.

The runtime owns the durable event pump, internal lifecycle, rebuild
serialization, and terminal pump-failure boundary. Applications own injected
stores and dispose the runtime before closing them. Closing an `EventStore`
also closes its `EventDatabase`.

## Command flow

1. A UI controller translates user intent into a typed command input.
2. A command obtains stream state, the runtime logger, IDs, and time through its
   `CommandContext`, declares existence/version constraints, and appends domain
   events.
3. The event store atomically records the command outcome and accepted event
   changes.
4. The event-store signal asks the runtime pump to read committed events.
5. The UI reads the resulting projection/read model rather than reconstructing
   domain state directly from the event store.

`execute` completes after durable command persistence and does not wait for
read-model updates. Automatic signals provide live eventual catch-up. Tests and
maintenance code may await `pump` when deterministic visibility is required.
Event persistence and read-model storage are not one transaction, so
projections remain resettable and replayable.

## Projection and read-model responsibilities

Applications define concrete domain event codecs, stream routes, projection
ownership, and query/read-model interfaces. Each projection declares a unique
name, a positive read-model version, one typed stream route and event handler,
reset behavior, and a batch callback. When a projection must consume unrelated
event types, it uses `Object` as its event type and checks the registry-decoded
event's runtime type in `apply`.

Core's runtime store owns progress for each globally unique projection name. A
projection reset must drop any
projection-owned schema and recreate its complete current schema. Missing or
mismatched runtime boundaries and projection-version changes cause selective
reset and replay from sequence zero. Unchanged projections resume after their
scanned-through local sequence. Intentional no-op events and pages with no route
matches still advance runtime-owned progress to the page end.

Read-model writes and runtime-store progress are not atomic with each other. An
interrupted apply or reset is detected by disagreeing boundaries on the next
startup, at which point the disposable read model is rebuilt from event history.

Keep a projection's write-model and read-model boundaries explicit. A UI query
may merge multiple disposable read models. If a feature requires deterministic
read-model visibility, it must explicitly await the pump instead of treating
durable command completion as projection completion.

Applications may notify UI controllers from `onBatchApplied`. An asynchronous
controller reload remembers notifications received during active work and runs
one trailing reload, preserving the final read-model state without a debounce.

## Current scope

The workspace's app is a local prototype. Apps must not claim multi-device sync,
encryption, device enrollment, blob storage, or backup until core contracts and
their application integration exist. See
[ARCHITECTURE_COMMON.md](ARCHITECTURE_COMMON.md) for shared infrastructure and
[SECURITY.md](SECURITY.md) for the present trust boundary.
