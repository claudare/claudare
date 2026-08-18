# Application patterns

This guide describes application-owned patterns built on CQRS. It does not add
CQRS APIs. Applications without domain separation keep event and projection
files directly in their respective folders.

## Event codecs

An event codec is the boundary between one application event type and its
persisted bytes. Define one `EventCodec<T>` for each concrete event type. Its
stable `kind` identifies the event in storage, while `toBytes` and `fromBytes`
handle only that event's payload.

Use stable, domain-specific event kinds. Once an event kind can be persisted,
do not rename or reuse it for a different payload. Every concrete event type
has one kind, one codec, and one payload format.

The application composition root registers every concrete codec once with
`CqrsRuntime` before initialization. The runtime's internal registry encodes
command events by Dart type and decodes stored events by kind. Commands and
projections do not receive codecs directly.

## Event-family layout

Keep application event families outside CQRS. Use a flat event and projection
layout until the application has an explicit domain boundary:

```text
lib/
  event/
    <event_family>.dart
    <event>_created.dart
    <event>_renamed.dart
    <event>_archived.dart
  command/
    create_<event>.dart
    rename_<event>.dart
  projection/
    <event>_projection.dart
    search_projection.dart
  read_model/
    <event>/
      <event>_read_model.dart
```

The event-family root file contains the sealed event root and declares the event
subtype files as `part` files. Each subtype file declares `part of` the root file
and contains one event class together with its concrete codec, stable kind, and
payload conversion.

Use `part` files only for a cohesive event family. They keep related variants
grouped while letting each event remain in its own file. Use ordinary imports
for commands, projections, read models, and shared helpers. Do not create
domain subdirectories before there is a domain boundary, and do not use `part`
to expose application internals as a package API.

## Adding an event

When adding an event to an existing family:

1. Add one subtype file and declare it from the family root.
2. Give it a new stable kind and define its payload conversion.
3. Add its concrete codec and register it with the application runtime.
4. Update the commands and projections that own its behavior.
5. Add codec, registry, and replay coverage for the new event.

The finance example in `packages/cqrs/test/example_app/finance/account_event`
is a test-only reference for this organization. Applications own their own
event families and codecs.

## Projections

Define a projection as one read-model owner with a unique name, a positive
model version, one typed `StreamRoute`, one typed `apply` handler, reset
behavior, and a required `onBatchApplied` callback:

```dart
final class AccountProjection implements Projection<AccountEvent, String> {
  @override
  StreamRoute<String> get streamRoute => accountStreamRoute;

  @override
  Future<void> apply(
    String accountId,
    AccountEvent event,
    EventMetadata metadata,
  ) async {
    // Apply the event to the read model.
  }
}
```

The runtime parses stream parameters from the matching path before invoking
`apply`. Use `Projection<Object, TParams>` when a projection intentionally
checks the registry-decoded event's runtime type itself.
