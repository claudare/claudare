# App Development Guide

Applications in `apps/*` own product behavior and compose the shared packages.
`apps/notes` is the current Flutter template: it demonstrates the expected
boundaries, but its note domain, database schema, and UI are not shared
architecture.

## Composition root

Give each application one composition root, similar to `NoteApplication`. It
should construct and retain the application-scoped dependencies that features
need:

- a `Logger`, `IdGenerator`, and `TimeProvider`;
- application-owned database connections and read-model repositories;
- an `EventDatabase` and `RuntimeDatabase` for `CqrsRuntimeDependencies`;
- an `EventRegistry` containing every application event codec;
- a `ProjectionRegistry` containing every application projection; and
- one `CqrsRuntime` that exposes command execution and explicit pumping.

Prefer constructor injection. Production startup can select SQLite, system time,
secure IDs, and console logging, while tests can select deterministic or
in-memory collaborators without changing domain code. Controllers receive the
composition root or focused interfaces from it rather than constructing storage
or runtime objects themselves.

Open application-owned databases before calling `CqrsRuntime.initialize()`.
Initialization migrates internal databases, prepares projections, and catches
read models up to durable event history before the interactive UI is exposed. On
shutdown, close the runtime first, dispose application notifiers, and then close
any databases not owned by the runtime. Closing the runtime closes its
`EventStore` and underlying `EventDatabase`; other application-owned databases
remain the application's responsibility.

## Application data flow

```text
UI action
  -> controller
  -> command
  -> EventStore
  -> projection
  -> read model
  -> controller notification
  -> UI
```

A controller translates user intent into a typed command input. The command uses
`CommandContext` for replaying and appending stream events. `EventStore` checks
for concurrency and durably persists events. Projections consume that durable
history and update application-owned read models. UI code queries those read
models instead of reconstructing state directly from event storage.

Command completion guarantees durable event persistence. It does not guarantee
that projections or the UI have observed the new events. The runtime requests
projection work asynchronously after a successful append. Code that needs
deterministic read-model visibility, especially a test or maintenance action,
must explicitly await `CqrsRuntime.pump()` after the command.

## Events and codecs

Applications own their event families and persisted formats. Define one
`EventCodec<T>` for every concrete event type. Its `kind` is the stable identity
stored with the event, and its byte conversion owns only that event's payload.
Once a kind can be persisted, do not rename it, reuse it for another event, or
silently change its payload meaning. Register each concrete codec exactly once
in the composition root before runtime initialization.

Keep the layout flat A cohesive event family may use a sealed root with one
`part` file per event:

```text
lib/
  event/
    note.dart
    note_created.dart
    note_title_updated.dart
  command/
    create_note.dart
    update_note_title.dart
  projection/
    note_projection.dart
  read_model/
    note/
      resolved_note_read_model.dart
```

The family root declares the event subtype files. Each subtype file contains one
event and its codec. Use ordinary imports for commands, projections, read
models, and helpers. When adding an event, add a new kind and codec, register
it, update the commands and projections that own its behavior, and cover codec
round trips and replay.

## Projections and read models

Each `Projection` owns one disposable read model. Give it a globally unique
name, a positive version, a typed `StreamRoute`, an `apply` handler, complete
reset behavior, and an `onBatchApplied` callback. A projection that deliberately
handles unrelated event types may use `Object` and dispatch on the decoded
runtime type in `apply`.

Events are authoritative state. A projection reset must remove all schema it
owns and recreate the complete current schema so the runtime can replay event
history from the beginning. A new projection version or interrupted progress
causes that projection to reset and replay; an unchanged projection resumes from
recorded progress. Read-model writes and progress recording are separate, so
read models must remain safe to discard and rebuild.

Use `onBatchApplied` to notify application listeners after committed projection
work. Controllers can respond by re-querying the read model and notifying
Flutter widgets. If notifications can arrive while a reload is running, use a
single-flight pattern such as `AsyncTrailingRunner` so one trailing reload
captures the newest state without overlapping queries.

## Controllers and persistence

Controllers own UI-facing state, translate gestures into commands or queries,
and subscribe to read-model notifications. They should remove listeners and
dispose their own Flutter objects when the screen closes. Expected command
rejections are `Exception` values that the controller can report or recover
from; fatal `Error` values are not UI control flow.

Applications own concrete persistence choices for their event store, runtime
progress, and read models. A feature may combine several read models behind an
application query interface, as Notes does for note data and search. Keep these
read paths explicit and do not let a disposable read model become an alternate
source of truth.

## Application tests

Test projections by applying events andreplaying from durable history. For
UI-facing behavior, await the pump before asserting read-model state. Keep
SQLite coverage where an application depends on schema, transaction, or
isolation behavior that an in-memory test cannot demonstrate.

See [Implementation Details](IMPLEMENTATION_DETAILS.md) for the shared package
architecture and [Security](SECURITY.md) for current capability limits.
