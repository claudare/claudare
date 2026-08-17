# Claudare summary

## Bottom line

Claudare is developing a reusable core for Dart and Flutter applications. Core
is a logical layer that will span multiple packages. It currently provides
local event-sourced command handling, optimistic stream locks, memory/SQLite
event databases behind a mutexed store, replayable projections, flat causal
command/event records, independent pending command and event persistence,
versioned per-projection page progress, IDs, time, logging, SQLite isolation,
and limited CRDT helpers in the separate `crdt` package.

`apps/notes` is the first prototype consumer. It gives feedback on core
contracts but does not define the architecture or public API for other apps.

## Core capability matrix

| Capability                                 | Current status                     |
| ------------------------------------------ | ---------------------------------- |
| Typed commands and optimistic stream locks | Implemented                        |
| Memory and SQLite local event stores       | Implemented                        |
| Flat causal records and pending persistence | Implemented locally               |
| Replayable application-defined projections | Implemented                        |
| Generic typed projections                   | Implemented                        |
| Consistent and eventual projection routing | Implemented                        |
| Version-selective projection rebuild        | Implemented                        |
| Runtime-owned projection page progress      | Implemented with mismatch rebuilds |
| Timestamp latest-write-wins helper         | Implemented with local-only limits |
| SQLite isolate boundary                    | Implemented                        |
| Explicit logging abstraction               | Implemented                        |
| Replication/import/export                  | Not implemented                    |
| Authenticated device identity              | Not implemented                    |
| Deterministic replicated convergence       | Not implemented                    |
| Event/database encryption                  | Not implemented                    |
| Blob storage or backup                     | Not implemented                    |

## Boundaries

- Core owns reusable CQRS contracts; `common` owns shared device, sequence, and
  serialization primitives; `id_generator` owns ID generation, `time_provider`
  owns time providers, and `crdt` owns CRDT value helpers.
- Applications provide domain codecs, projections, storage selection, UI, and
  lifecycle.
- Notes is a prototype consumer of core.

## Priorities

1. Repair core persistence correctness, parity, and lifecycle.
2. Define stable core APIs and projection lifecycle contracts.
3. Specify replication and convergence before transport.
4. Add identity, reviewed cryptography, and backup after the core data model.

## Documentation map

- [ARCHITECTURE_ECOSYSTEM.md](ARCHITECTURE_ECOSYSTEM.md): general overview of
  the Claudare project.
- [ARCHITECTURE_COMMON.md](ARCHITECTURE_COMMON.md): reusable core contracts.
- [ARCHITECTURE_APPS.md](ARCHITECTURE_APPS.md): application composition.
- [APP_PATTERNS.md](APP_PATTERNS.md): application-owned concrete event codecs,
  runtime registration, and layout.
- [IMPLEMENTATION.md](IMPLEMENTATION.md): current core behavior and prototype
  evidence.
- [SECURITY.md](SECURITY.md): core security boundaries and future gates.
- [IMPROVEMENTS.md](IMPROVEMENTS.md): prioritized core work.
