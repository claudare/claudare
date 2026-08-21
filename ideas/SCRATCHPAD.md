# Ideas scratchpad

This is an ideation document. It is non-authoritative and is used to keep ideas
in one place. For better defined and conrete documentation read markdowns at
`docs`.

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
- Use a separate mutex for the replicated commands/events in the event store.
  They dont need to block applied ones.
- Remove the string interpolations from `StreamIdPattern`. Instead use
  `id` and `kind`. ID and kind are always a strings?

## Interesting libraries

### Device communication

The native Flutter platforms considered here are Android, iOS, Linux, macOS,
and Windows. Flutter web does not expose general TCP or UDP sockets and cannot
provide the same Bluetooth roles.

#### Wi-Fi and Ethernet

- [`dart:io`](https://api.dart.dev/dart-io/) provides built-in TCP clients and
  listeners through `Socket` and `ServerSocket`, and UDP through
  `RawDatagramSocket`. It is the lowest-dependency baseline and can listen on
  mobile devices while the application is allowed to run. Repository:
  [dart-lang/sdk](https://github.com/dart-lang/sdk/tree/main/sdk/lib/io).
- [`dart_udx`](https://pub.dev/packages/dart_udx) provides reliable, ordered,
  multiplexed streams over UDP on all native Flutter platforms. Keep it behind
  the pipe abstraction because it is a young, custom transport implementation.
  Repository: [stephanfeb/dart_udx](https://github.com/stephanfeb/dart_udx).

For mDNS discovery and advertisement:

- [`bonsoir`](https://pub.dev/packages/bonsoir) supports service discovery and
  broadcasting on all native Flutter platforms. Repository:
  [Skyost/Bonsoir](https://github.com/Skyost/Bonsoir).
- [`multicast_dns`](https://pub.dev/packages/multicast_dns) is the Flutter-team
  package for mDNS queries on all native platforms. It is suitable for
  discovery, but does not replace a service advertiser. Repository:
  [flutter/packages](https://github.com/flutter/packages/tree/main/packages/multicast_dns).

Opening a TCP or UDP listener and advertising it through mDNS are separate
operations. Android and iOS permissions, application lifecycle, and background
execution can still prevent a mobile listener from remaining continuously
available.

#### Bluetooth Low Energy

- [`bluetooth_low_energy`](https://pub.dev/packages/bluetooth_low_energy)
  supports the central role on Android, iOS, Linux, macOS, and Windows. Its
  peripheral role supports Android, iOS, macOS, and Windows, but not Linux.
  Repository:
  [yanshouwang/bluetooth_low_energy](https://github.com/yanshouwang/bluetooth_low_energy).
- [`universal_ble`](https://pub.dev/packages/universal_ble) supports the central
  role across Android, iOS, Linux, macOS, Windows, and web. Its peripheral role
  supports Android, iOS, macOS, and Windows, but not Linux or web. Repository:
  [Navideck/universal_ble](https://github.com/Navideck/universal_ble).
- [`omni_ble`](https://pub.dev/packages/omni_ble) intends to support both roles
  across all five native platforms, including Linux peripheral mode. It is
  currently an early development release and not ready as a stable dependency.
  Repository: [Atrac613/omni_ble](https://github.com/Atrac613/omni_ble).

There is currently no clearly production-ready Flutter BLE package with fully
validated central and peripheral behavior across every native platform.
Runtime capability detection and real-device testing are required. BLE adapters
must also provide fragmentation, reassembly, flow control, and bounded buffering
below the whole-payload pipe abstraction.

### Serialization

- [messagerpack library, good manual workflow](https://pub.dev/packages/messagepack)
- [msgpack_dart, automatic type derivation](https://pub.dev/packages/msgpack_dart)

### Database

- [nosql hive](https://pub.dev/packages/hive)
