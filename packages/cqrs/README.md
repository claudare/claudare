# cqrs

CQRS implementation for the Claudare workspace.

`MemoryNotificationBus` delivers in-process notifications synchronously to
listeners whose stream filters match. Subscriptions can be canceled;
notifications are not persisted or replayed.

`NotificationBusListener.stream` exposes matching paths as an asynchronous,
single-subscription stream. Canceling its listener unregisters from the bus.
The callback-based `listen` API remains synchronous. `CqrsRuntime.subscribe`
exposes notifications without resolving aggregates; callers choose when to
query or resolve state.

`EventStore` is implemented by `MemoryEventStore` and `SqliteEventStore`.
The memory store is ready on construction. Call `SqliteEventStore.migrate()`
before using SQLite; the concrete SQLite store also owns database close.

`CqrsRuntime` requires an actor string and a notification bus. `CommandId` and
`CommandDependency` identify commands and their causal dependencies using those
strings.
`StoredCommand` is the replication boundary: `addStoredCommand` and
`getStoredCommand` preserve its identity and dependencies across stores.
Command sequences start at one. Actors have no public-key validation or
registration.

Test helpers `CqrsTestRuntime` and `CommandTester` use an internal test actor and
need no initialization. Injected SQLite stores must already be migrated.

## Positions

Command, log event, and stream reads are inclusive of the requested position.
`null` means an empty command or event history when returned as its last log
sequence, or an absent stream when used as its version.

## Validation

Run the package tests from this directory with:

```sh
fvm dart test
```

Exercise order independence with:

```sh
fvm dart test --test-randomize-ordering-seed=random
```

Collect branch coverage with:

```sh
./coverage.sh
```

The script writes LCOV data to `coverage/lcov.info` and a human-readable report
to `coverage/html/index.html`.
