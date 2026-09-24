# App Development Guide

Applications in `apps/*` own product behavior and compose the shared packages.
`apps/notes` is one example. Its note events, commands, aggregates, and UI are
application-specific.

## Event-sourced flow

```text
user action -> application command -> durable stream events
user view   -> application query   -> aggregate replay -> UI
```

Commands read the streams needed to validate a change and append events. The
event store checks stream versions when saving, so a stale concurrent command
can fail with `ConcurrencyProblem`. A successful command has stored its events.

Queries resolve aggregates from stored events. Notes uses this for note details,
lists, and counts. The UI refreshes its queries after local commands and when
returning from another screen. The Notes application has no separate search or
projection database.

## Application composition

Keep storage lifecycle at the application boundary. The Notes bootstrap opens
and migrates `events.sqlite`, constructs the event store and `CqrsRuntime`, and
closes the SQLite connection on shutdown or failed initialization.
`NoteApplication` registers the note event codecs and exposes `command` and
`query` methods. Controllers depend on that application API.

See [Implementation Details](IMPLEMENTATION_DETAILS.md) for package ownership
and [Security](SECURITY.md) for the current security posture.
