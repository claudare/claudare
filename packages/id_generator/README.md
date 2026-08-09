# id_generator

128-bit ID generators for the Claudare workspace.

`id_generator.dart` exports the `IdGenerator` contract and secure, seeded,
sequential, and static implementations. Every implementation produces 16-byte
values and 22-character unpadded base64url IDs. Use the secure implementation
for production and the deterministic implementations for tests and fixtures.
