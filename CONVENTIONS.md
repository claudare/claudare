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
  such as `MemoryEventStore`.
- Inject storage, time, IDs, logging, and similar collaborators through
  constructors. Name substitutes by role, such as `Memory`, `Fake`, `System`,
  `Random`, `Seeded`, or `Sequential`.
- Treat in-memory implementations as behavioral references. Side-effecting
  implementations must match them; add parity or table-driven tests where
  implementations or edge cases could diverge.
- Prefer one class per file. Related interfaces or cohesive domain types may
  share a file. Use nested implementation folders only when they clarify
  ownership.
- Use `*_safe.dart` wrappers for assertions and exception translation. Keep
  package exceptions in a shared exception folder.

## Errors and invariants

- Catch `Exception` only for recovery or translation. Let `Error` propagate.
- Preserve stack traces when translating exceptions. Narrow handling of known
  encoding or decoding failures may add context but must not hide other faults.
- Use assertions for defensive invariants.
