# id_generator

String ID generators for the Claudare workspace.

`id_generator.dart` exports the `IdGenerator` contract and random, sequential,
and static implementations. Random IDs are UUID v4 strings. Sequential IDs are
decimal strings starting at `1`. Static IDs repeat the configured string.
Use sequential or static generators for deterministic tests and fixtures.
