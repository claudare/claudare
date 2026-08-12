# Ideas scratchpad

This is an ideation document. It is non-authoritative and is used to keep ideas
in one place. For better defined and conrete documentation read markdowns at
`docs`.

## Interesting ideas

- Postfix the class with `Mutable`?

## Maybe todo's?

- Current device id is 0.
- Map device public key to locally incrementable uint device id.
- Define protocols as sync state machines.
- Try to define as many constants as possible. Fail on violations.
- No central centralization mentality (optimization) for now. All data is
  encrypted and sent to to all devices separately; Events or blobs. Everyone
  stores everything.
- Push vs pull for sync... Not sure, but I am leaning towards the push model.

## Interesting libraries

### Serialization

- [messagerpack library, good manual workflow](https://pub.dev/packages/messagepack)
- [msgpack_dart, automatic type derivation](https://pub.dev/packages/msgpack_dart)

### Database

- [nosql hive](https://pub.dev/packages/hive)
