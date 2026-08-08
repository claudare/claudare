# Application patterns

This guide describes application-owned patterns built on Core. It does not add
Core APIs or require every application to use the same domain layout.

## Event codecs

An event codec is the boundary between an application's typed domain events
and Core's stored `EncodedEvent` values. Define one codec for each closed domain
event family. The codec encodes an event's payload and event kind for storage,
then uses that kind to recreate the correct event subtype during replay.

Use stable, domain-specific event kinds. Once an event kind can be persisted,
do not rename or reuse it for a different payload. Every event subtype has one
kind, its payload serialization, and deserialization. The codec maps every
subtype in both directions and rejects an unknown kind rather than interpreting
it as another event.

Commands emit the typed events through their stream context. Projections
receive the same codec and use its decoded events to update application-owned
read models. The application composition root supplies the codec where commands
and projections are wired.

## Event-family layout

Keep each event family beside its domain rather than in Core. A typical layout
is:

```text
lib/
  domain/
    <feature>/
      <feature>_event/
        <feature>_event.dart
        <feature>_created.dart
        <feature>_renamed.dart
        <feature>_archived.dart
      command/
        create_<feature>.dart
        rename_<feature>.dart
      projection/
        <feature>_projection.dart
      read_model/
        <feature>_read_model.dart
```

The event-family root file contains the sealed event root and its codec. It
declares the event subtype files as `part` files. Each subtype file declares
`part of` the root file and contains one event class, including its stable kind
and payload conversion.

Use `part` files only for a cohesive event family whose root and codec must
share one Dart library. They keep related variants grouped while letting each
event remain in its own file. Use ordinary imports for independent domain
types, commands, projections, read models, and shared helpers. Do not use
`part` to cross feature boundaries or to expose application internals as a
package API.

## Adding an event

When adding an event to an existing family:

1. Add one subtype file and declare it from the family root.
2. Give it a new stable kind and define its payload conversion.
3. Add the encoding and decoding mappings to the family codec.
4. Update the commands and projections that own its behavior.
5. Add codec and replay coverage for the new event.

The finance example in `packages/core/test/example_app/finance/account_event`
is a test-only reference for this organization. Applications own their own
event families and codecs.
