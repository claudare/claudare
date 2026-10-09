# crdt

Use collaborative text when concurrent edits should be combined, or a
last-write-wins string when one complete value should win.

Edit through a context, persist its prepared changes, then apply them to the
document. Each independent writer needs a distinct actor ID. Incoming text
changes require causal delivery, and document snapshots exclude unsaved edits.

Editor bindings work with a consumer-supplied controller, without a Flutter
dependency. The caller supplies persistence and change delivery; this package
does not provide networking, rich text, or a complete synchronization system.
