# Ideas scratchpad

This is an ideation document. It is non-authoritative and is used to keep ideas
in one place. For better defined and conrete documentation read markdowns at
`docs`.

## Interesting ideas

- Postfix the class with `Mutable`?

## TODOs

- Generate localSequences and logical clocks in code. Run everything inside a
  mutex (an async queue) and rollback ids on failures. It is extremely important
  that no "holes" are present in sequential ids.
- Remove the sequence from the async_fifo_queue. Add queueWait method for a
  Future return like a mutex.
- Create prod and testing `CqrsRuntimeConfig`. Rename to
  `CqrsRuntimeDependencies`.
- Move the event fetch page size outside the `EventStore`.

## Maybe todo's?

- Current device id is 0.
- Map device public key to locally incrementable uint device id.
- Define protocols as sync state machines.
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
