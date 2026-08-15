# common

Shared causal and serialization primitives for the Claudare workspace.

`common.dart` exports dots, version vectors, and the JSON byte converter. A dot
uses an unrestricted database-local integer device ID and a positive sequence.
Version vectors serialize integer keys in deterministic order.

These primitives do not provide authenticated device identity or a replication
protocol. Peer communication owns translation from stable peer identity to
database-local integer IDs.
