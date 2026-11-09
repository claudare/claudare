# Notes core

Notes behavior in a Dart application without its Flutter interface.
It supports creating, editing, trashing, restoring, and querying notes.
Supply a CQRS runtime to connect it to event storage.

Start projections before searching and cancel the run when finished:

```dart
final run = application.startProjections();
await run.ready;
final matches = await application.query.noteSearch('meeting');
await run.cancel();
```

The [Notes app](../../frontends/notes/README.md) provides the user interface.
