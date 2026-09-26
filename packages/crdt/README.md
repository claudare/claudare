# crdt

Text CRDT and timestamp-based value helpers for the Claudare workspace. Import
the text API through `package:crdt/crdt_text.dart`.

## Text

`CrdtText()` is mutable document state with deterministic RGA merging. It
accepts `CrdtTextChange` batches and supports complete JSON snapshots without
requiring a local actor ID. It depends only on Dart SDK libraries.

`CrdtTextEditContext(document: document, actorId: actorId)` copies the document
into a private draft with insert, delete, and replace operations. Supply an
actor ID for each independent writer. Offsets and `length` use UTF-16, matching
Dart strings and Flutter selections. Edits must fall on Unicode scalar
boundaries; malformed strings and split surrogate pairs are rejected. Combining
sequences are preserved without normalization or grapheme-level conflict rules.

Incoming changes require causal delivery. Missing dependencies and conflicting
operation IDs throw `CrdtTextException` without partially applying a batch.
Exact duplicates are accepted. The caller provides delivery and persistence.

Call `prepareChange()` on the context to obtain unsaved local edits, persist its
JSON in the event log, then call `acknowledgeChange(change)`. Until
acknowledgment, preparation returns the same immutable batch for retries.
Edits made while saving remain pending for the next batch. Replayed events are
never included in local pending edits. Editing and acknowledgment do not update
the original document. Apply persisted changes to it explicitly, and deliver
incoming changes to the context with `applyChange()` to update the draft.

`CrdtText.toJson()` and `CrdtText.fromJson()` preserve document history,
including operation actor IDs and tombstones. Snapshots contain no local writer
identity, pending edits, or prepared batch. A restored document can be edited
through a fresh context for any actor.

Contexts exist only in memory. Discarding one loses its unsaved edits. See the
[usage example test](test/text/crdt_text_usage_example_test.dart) for editing,
persistence, replay, and snapshot restoration without application dependencies.

## Editors

`CrdtTextBinding(editContext: context, controller: controller)` connects the
editing draft to a `CrdtTextController`. This small interface exposes one
complete editing value and listener registration. Its value includes text,
selection, visual affinity, directionality, and composing range. A consumer's
Flutter adapter maps these to `TextEditingController.value` and forwards its
listener methods; this package does not import Flutter.

Binding initializes the editor from the draft with the caret at the end.
Selections follow character anchors through remote edits. During composition,
draft-driven editor refreshes wait until composition ends while local and
remote draft edits continue. Dispose the binding to detach its listeners; the
caller retains ownership of the controller.

## Limits and validation

This package does not provide networking, CQRS integration, historical queries,
rich text, compression, or a complete synchronization system. Operation history
is retained, and large documents have not been optimized for time or memory.

Tests cover editing, causal rejection, convergence, JSON persistence, save
retries, and editor behavior using a pure Dart fake controller. Flutter platform
and IME behavior has not been verified at runtime. From this package, run
`fvm dart test --reporter failures-only`; run `fvm dart analyze` from the
workspace root.

## Value

`CrdtValueLatestWriteWins` and its value/timestamp pair remain available. Equal
timestamps retain the incoming value; this helper has no actor tie-breaker.
