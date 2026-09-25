# crdt

Text CRDT and timestamp-based value helpers for the Claudare workspace. Import
the public API through `package:crdt/crdt.dart`.

## Text

`CrdtText` is mutable plain text with deterministic RGA merging. It supports
insert, delete, and replace operations, incoming `CrdtTextChange` batches, and
complete JSON snapshots. It depends only on Dart SDK libraries.

Supply a distinct, nonempty string actor ID for each independent writer. Offsets
and `length` use UTF-16, matching Dart strings and Flutter selections. Edits
must fall on Unicode scalar boundaries; malformed strings and split surrogate
pairs are rejected. Combining sequences are preserved without normalization or
grapheme-level conflict rules.

Incoming changes require causal delivery. Missing dependencies and conflicting
operation IDs throw `CrdtTextException` without partially applying a batch.
Exact duplicates are accepted. The caller provides delivery and persistence.

Call `prepareChange()` to obtain unsaved local edits, persist its JSON in the
event log, then call `acknowledgeChange(change)`. Until acknowledgment,
preparation returns the same immutable batch for retries. Edits made while
saving remain pending for the next batch. Replayed events are never included in
local pending edits.

`toJson()` and `CrdtText.fromJson()` preserve the document and pending save
state, including a prepared batch. Export does not acknowledge changes.
Restoration resumes the same actor; initialize a different writer with a new
actor ID and replay saved changes. Changes also support JSON round trips.

## Editors

`CrdtTextBinding` connects the document to a `CrdtTextController`. This small
interface exposes one complete editing value and listener registration. Its
value includes text, selection, visual affinity, directionality, and composing
range. A consumer's Flutter adapter maps these to `TextEditingController.value`
and forwards its listener methods; this package does not import Flutter.

Binding initializes the editor from the document with the caret at the end.
Selections follow character anchors through remote edits. During composition,
document-driven editor refreshes wait until composition ends while local and
remote document edits continue. Dispose the binding to detach its listeners; the
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
