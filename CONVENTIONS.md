# Core wiring conventions

Core is Claudare's reusable, application-independent logical layer across shared
packages. `apps/notes` consumes Core but does not define its architecture or API.
These conventions apply to new and modified code, not unrelated existing
deviations.

## Contracts and implementations

- Treat public package entrypoints as consumer boundaries. Consumers must not
  import `src`; Core implementations and white-box tests may do so when needed.
- Prefer small, composable `abstract interface class` contracts. Aggregate
  interfaces may compose capabilities but must not expose storage or runtime
  details.
- Name contracts for their domain without suffixes such as `Repository`,
  `Service`, or `Implementation`. Prefix concrete types with the domain name,
  such as `MemoryEventDatabase`.
- Inject storage, time, IDs, logging, and similar collaborators through
  constructors. Name substitutes by role, such as `Memory`, `Fake`, `System`,
  `Random`, `Seeded`, or `Sequential`.
- Treat in-memory implementations as behavioral references. Side-effecting
  implementations must match them; add parity or table-driven tests where
  implementations or edge cases could diverge.
- Prefer one class per file. Related interfaces or cohesive domain types may
  share a file. Use nested implementation folders only when they clarify
  ownership.
- Put invariant enforcement and exception translation in the public owner of
  the operation. Keep raw persistence adapters free of ID and clock allocation.

## Errors and invariants

- `Error` is fatal throughout the repository and bubbles unchanged to the
  application boundary, where it can crash the app. Never throw an `Error` for
  an expected, non-fatal condition. Use an `Exception` for validation, rejected
  commands, stale state, and other recoverable outcomes.
- `CommandException` is the conventional CQRS exception for command rejection,
  but applications may use any `Exception`. Its use is not required. Application
  commands must not use `StateError`, `ArgumentError`, assertions, or another
  `Error` for non-fatal control flow.
- Handle `Exception` where recovery, reporting, or translation is needed.
  Otherwise let it propagate. Do not handle `Error`. The explicit exceptions
  are `EventCodecSafe` and `CommandCodecSafe`, which translate every codec
  failure, including `Error`, to their CQRS exception types.
- Preserve stack traces when translating exceptions. Narrow handling of known
  encoding or decoding failures may add context but must not hide other faults.
- Use assertions for defensive invariants.
