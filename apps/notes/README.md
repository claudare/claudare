# notes

## Logging

Production uses one application-scoped `ConsoleLogger` named `notes` with a
minimum level of `debug`. The same logger is shared by the CQRS runtime and
Notes-owned commands, projections, repositories, controllers, and screens.

`NoteApplication.test()` uses `NoopLogger` by default. Tests that inspect
diagnostics can inject a `RecordingLogger` through `logger`.
