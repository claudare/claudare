# common

Shared device, sequence, and serialization primitives for the Claudare
workspace.

`common.dart` exports device IDs, device/causal sequence helpers, and the JSON
byte converter. These primitives do not provide authenticated device identity
or a replication protocol.

Device IDs are local to a database. Zero always identifies the current device;
positive values are available for incrementally assigned other devices.
