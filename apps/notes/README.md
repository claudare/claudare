# Notes core

`notes_app` is the Dart package for note cqrs and behavior. It owns note
aggregates, commands, events, and paths. Callers use `NotesApp` with a supplied
`CqrsRuntime` to create, edit, trash, restore, and query notes. The public
entrypoint also exposes the note state and query option types needed by
consumers.

The [Flutter frontend](../../frontends/notes/README.md) owns platform setup,
storage lifecycle, and UI. The core has no Flutter dependency. It does not
provide replication, encryption, or backup.
