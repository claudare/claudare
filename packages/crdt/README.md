# crdt

CRDT value helpers for the Claudare workspace.

`crdt.dart` exports a latest-write-wins value and its value/timestamp pair.
Equal timestamps retain the incoming value. This is not a complete replicated-
data system and provides no deterministic actor tie-breaker or text CRDT.
