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
          -> bound consistent projections -> awaited read models
          -> bound eventual projections   -> asynchronous read models
          -> unbound matching projections -> asynchronous read models
```

At startup, the composition root creates the event store, runtime store,
projections, read models, logger, ID generator, time provider, and
database owners. It registers one codec per concrete event type with the CQRS
runtime, then opens storage, applies migrations, and initializes the runtime
before exposing interactive UI.

This is the current pre-Stage-7 production path. Applications still choose
bound consistent and eventual projection delivery, and the production runtime
does not yet own the isolated durable event pump or its planned lifecycle and
failure boundary. The future cutover is specified in
[`ideas/RUNTIME_REWORK.md`](../ideas/RUNTIME_REWORK.md), but that plan is not
implemented behavior. No consistent projections will be used after runtime
rework is implemented.

## Command flow

1. A UI controller translates user intent into a typed command input.
2. A command obtains stream state, the runtime logger, IDs, and time through its
   `CommandContext`, declares existence/version constraints, and appends domain
   events.
3. The event store atomically records the command outcome and accepted event
   changes.
4. The runtime routes committed events to projections.
5. The UI reads the resulting projection/read model rather than reconstructing
   domain state directly from the event store.

In the current runtime, `bindCommand` lets applications choose which projections
are **consistent**.
The bound command waits for those projection callbacks before reporting
success, while its other projections are **eventual** and may lag. With
`executeCommand`, every matching registered projection is dispatched
asynchronously. Its future completes after durable command persistence and
queue dispatch, without waiting for read-model updates. None of these modes
makes event persistence and read-model storage one transaction; projections
must remain resettable and replayable.

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
must state whether it reads a consistent model, an eventual model, or a merged
result from multiple models. If a feature depends on durable visibility before
navigation, the application must wait for the appropriate command/projection
boundary rather than relying on widget disposal or post-navigation work.

## Current scope

The workspace's app is a local prototype. Apps must not claim multi-device sync,
encryption, device enrollment, blob storage, or backup until core contracts and
their application integration exist. See
[ARCHITECTURE_COMMON.md](ARCHITECTURE_COMMON.md) for shared infrastructure and
[SECURITY.md](SECURITY.md) for the present trust boundary.
