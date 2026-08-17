# Application architecture

## Purpose

Applications in `apps/*` own product behavior and compose the reusable core.
They turn UI actions into domain commands, choose core persistence and read-model
implementations, and render projections. An application may depend on shared
packages; shared packages must not depend on applications.

This document describes the general application flow. Domain-specific screens,
event kinds, tables, and product features belong in their owning application.

## Composition flow

```text
UI
  -> application composition root
      -> CqrsRuntime
          -> event store
          -> consistent projections -> read models used by the command response
          -> eventual projections   -> asynchronous read models
```

At startup, the composition root creates the event store, runtime-version
repository, projections, read models, logger, ID generator, time provider, and
database owners. It registers one codec per concrete event type with the CQRS
runtime, then opens storage, applies migrations, and initializes the runtime
before exposing interactive UI.

The application owns this lifecycle: initialization must be single-flight,
errors must reach a defined UI state, and shutdown must close runtime queues and
storage owners.

## Command flow

1. A UI controller translates user intent into a typed command input.
2. A bound command obtains stream state through its `CommandContext`, declares
   existence/version constraints, and appends domain events.
3. The event store atomically records the command outcome and accepted event
   changes.
4. The runtime routes committed events to projections.
5. The UI reads the resulting projection/read model rather than reconstructing
   domain state directly from the event store.

Applications choose which projections are **consistent** for a command. The
command waits for those projection callbacks before reporting success. Other
projections are **eventual** and may lag. Neither mode makes event persistence
and read-model storage one transaction; projections must remain resettable and
replayable.

## Projection and read-model responsibilities

Applications define concrete domain event codecs, stream routes, projection
ownership, and query/read-model interfaces. Each projection declares a unique
name, a positive read-model version, an ordered list of typed routes, reset
behavior, and a batch callback. A projection may consume multiple unrelated
event families and stream routes. When event selection genuinely belongs at
runtime, applications use an `Object` event route and check the registry-decoded
event's runtime type in the handler.

Core's runtime store owns progress for each globally unique projection name. A
projection reset must drop any
projection-owned schema and recreate its complete current schema. Missing or
mismatched runtime boundaries cause reset and replay from sequence zero.
Intentional no-op events still advance runtime-owned progress.

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
