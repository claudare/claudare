# cqrs

CQRS implementation for the Claudare workspace.

`EventStore` is implemented by `MemoryEventStore` and `SqliteEventStore`.
The memory store is ready on construction. Call `SqliteEventStore.migrate()`
before using SQLite; the concrete SQLite store also owns database close.

`CqrsRuntime` requires an actor string. `CommandId` and `CommandDependency`
identify commands and their causal dependencies using those strings.
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
