# Ideas scratchpad

This is an ideation document. It is non-authoritative and is used to keep ideas
in one place. For better defined and conrete documentation read markdowns at
`docs`.

## Interesting ideas

- Postfix the mutating classes with `Mutable`?

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
- Push model for event sync. Replicate commands and events out of order. Use the
  ids as unique identifiers. Use them for deduplication.
- Pull model for blob sync. Get inspired by by Bittorrent protocol: use want,
  interested, choked, and unchoked concepts.
- Remove the string interpolations from `StreamIdPattern`. Instead use
  `id` and `kind`. ID and kind are always a strings?

## Interesting libraries

### Serialization

- [messagerpack library, good manual workflow](https://pub.dev/packages/messagepack)
- [msgpack_dart, automatic type derivation](https://pub.dev/packages/msgpack_dart)

### Database

- [nosql hive](https://pub.dev/packages/hive)
