# Notes core

Notes behavior in a Dart application without its Flutter interface.
It supports creating, editing, trashing, restoring, and querying notes.
Supply a CQRS runtime to connect it to event storage.

Start projections before searching and stop them when finished:

```dart
application.startProjections();
await application.query.searchReady;
final matches = await application.query.noteSearch('meeting');
await application.stopProjections();
```

The [Notes app](../../frontends/notes/README.md) provides the user interface.
