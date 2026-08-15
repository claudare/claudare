# Ideas scratchpad

This is an ideation document. It is non-authoritative and is used to keep ideas
in one place. For better defined and conrete documentation read markdowns at
`docs`.

## Interesting ideas

- Postfix the class with `Mutable`?

## TODOs

- Rethrow the original errors. Good point to fix is `ConcurrencyProblem` in the
  event store safe.
## Maybe todo's?

- Map peer identity to a database-local integer device ID before CQRS import.
- Define protocols as sync state machines.
- Transport command metadata and indexed events independently.
- Schedule explicit promotion outside CQRS after pending records become ready.
- Try to define as many constants as possible. Fail on violations.
- No central server. Peer to peer communication only.
- No encryption of the stored data. However, the data is encrypted in transit
  only and sent to to all devices separately; Events or blobs: every device
  stores everything.
- Push model for sync. The blob protocol is insired by Bittorrent: uses want,
  interested,

## Interesting libraries

### Serialization

- [messagerpack library, good manual workflow](https://pub.dev/packages/messagepack)
- [msgpack_dart, automatic type derivation](https://pub.dev/packages/msgpack_dart)

### Database

- [nosql hive](https://pub.dev/packages/hive)
