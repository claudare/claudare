# App Development Guide

Dart packages in `apps/*` own product behavior and compose the shared packages.
Flutter applications in `frontends/*` own their UI and platform setup.
`apps/notes` owns note events, commands, and aggregates;
`frontends/notes` consumes that behavior.

## Event-sourced flow

```text
user action -> application command -> durable stream events
user view   -> application query   -> aggregate replay -> UI
```

Commands read the streams needed to validate a change and append events. The
event store checks stream versions when saving, so a stale concurrent command
can fail with `ConcurrencyProblem`. A successful command has stored its events.

Queries resolve aggregates from stored events. Notes uses this for note details,
lists, and counts. The notes list refreshes after note stream changes and when
returning from another screen. The Notes application has no separate search or
projection database.

## Application composition

Keep storage lifecycle at the frontend boundary. The Notes bootstrap opens and
migrates local SQLite storage, constructs the event store and `CqrsRuntime`, and
closes the SQLite connection on shutdown or failed initialization. `NotesApp`
registers note event codecs and exposes `command` and `query` methods.
Controllers depend on that application API.

Prefer an `InheritedWidget` provider for dependencies shared by screens, read
with `of(context)`. Constructor injection is also fine when it is simpler,
especially for plain Dart controllers.

See [Implementation Details](IMPLEMENTATION_DETAILS.md) for package ownership
and [Security](SECURITY.md) for the current security posture.
