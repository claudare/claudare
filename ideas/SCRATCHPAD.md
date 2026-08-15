# Ideas scratchpad

This is an ideation document. It is non-authoritative and is used to keep ideas
in one place. For better defined and conrete documentation read markdowns at
`docs`.

## Interesting ideas

- Postfix the class with `Mutable`?

## TODOs

- Generate localSequences and logical clocks in code. Run everything inside an
  exclusive mutex and rollback ids on failures. It is extremely important
  that no "holes" are present in sequential ids.
- Add a RW mutex to the `MemoryEventStore`, and use it for read operations too?
  Or maybe the mutex here is not needed and concurrency is enforced outside?
- Rethrow the original errors. Good point to fix is `ConcurrencyProblem` in the
  event store safe.
- Do not save failed command exceptions. like `CommandResult.exception(exception: cause)`.
  Exceptions are just rethrown (or the case of CommandExecutor they are not
  caught. Add a comment where command is handled)

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
