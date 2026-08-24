# App Development Guide

Applications in `apps/*` own product behavior and compose the shared packages.
`apps/notes` is the current example of this composition. Its domain, database
schema, and UI are application-specific rather than shared architecture.

This guide introduces the event-sourcing model exposed by the current `cqrs`
package. See [Implementation Details](IMPLEMENTATION_DETAILS.md) for runtime and
storage internals.

## Event-sourced application flow

```text
user intent
  -> command
  -> stream events
  -> durable event history
  -> asynchronous projections
  -> read models
  -> onBatchApplied
  -> UI
```

Events are the authoritative record of what happened in the application. They
are grouped into streams, which represent the history relevant to a particular
domain entity or process. Projections consume that history to maintain
disposable read models optimized for application queries.

## Commands, streams, and events

Events enter the system only through commands. A command receives a
`CommandContext`, opens the streams it needs, and reads their events to
reconstruct the relevant current state. It should use that state to decide
whether the requested action is valid and preserves the application's data
model.

If the action is valid, the command appends new events to the streams. The
append checks that the streams have not changed since the command read them. A
concurrent change causes the command to throw `ConcurrencyProblem`; callers
should handle or retry that outcome where appropriate.

When a command completes successfully, its events are durable. Command
completion does not wait for projection catch-up, so it does not mean that read
models or the UI have observed those events yet.

## Projections and read models

Projections run asynchronously and eventually catch up with durable event
history. A projection accepts the read model it maintains through its
constructor, applies relevant events to it, and may notify the application after
a batch has been applied through `onBatchApplied`. Controllers should observe
that notification, query the updated read model, and refresh the UI as one batch
update rather than assuming command completion made the changes visible.

Never allow a projection to throw. A projection failure transitions the CQRS
runtime into its terminal error state. Projection state is disposable, so a
projection should do its best to repair, replace, or ignore inconsistent derived
state while applying authoritative events. It must also be able to reset all
state it owns so the runtime can rebuild it from event history.

Because projections are asynchronous, normal UI code should tolerate read models
that are briefly behind and use `onBatchApplied` to observe catch-up. Tests,
maintenance work, or application flows that require the read models to be
current must explicitly await `CqrsRuntime.pump()` after the command. Once the
pump completes, the applicable projection batches and their `onBatchApplied`
notifications have run.

## Read-model interfaces

Define separate interfaces for projection writes and application reads. It is
usually useful for one application-owned database class to implement both:

- a mutating interface used only by the projection; and
- a read-only interface used by controllers and other read-model consumers.

Pass the mutating interface into the projection and expose only the read-only
interface to query consumers. This keeps write ownership with the projection,
makes dependencies explicit, and allows the database implementation to be
replaced without changing domain or UI code.

## Application composition

Give each application one composition root. It should construct the
application-owned databases, register the application's event codecs and
projections, create the `CqrsRuntime`, and inject focused interfaces into
commands, projections, controllers, and other consumers. Expose the read models
on the application. Prefer constructor injection so tests can substitute
deterministic or in-memory implementations.
