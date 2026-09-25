# Coding conventions

These conventions apply to new and modified shared code. `apps/notes` consumes
the shared packages but does not define their architecture or APIs.

## Contracts and implementations

- Treat public package entrypoints as consumer boundaries. Consumers must not
  import `src`. Package implementations and white-box tests may do so when
  needed.
- Prefer small, composable `abstract interface class` contracts. Aggregate
  interfaces may compose capabilities but must not expose storage or runtime
  details.
- Name contracts for their domain without suffixes such as `Repository`,
  `Service`, or `Implementation`. Prefix concrete types with their role or
  mechanism, such as `MemoryEventStore`.
- Inject side-effects such as storage, time, IDs, logging, and similar
  collaborators through constructors.
- Treat in-memory implementations as behavioral references. Database backed
  implementations must match them. Add parity or table-driven tests where
  implementations or edge cases could diverge.
- Prefer one class per file. Related interfaces or cohesive domain types may
  share a file. Use nested implementation folders only when they clarify
  ownership.
- Put invariant enforcement and exception translation in the public owner of the
  operation. Keep raw persistence adapters free of ID and clock allocation.

## Logging

- Pass `Logger` explicitly through constructors. Use `NoopLogger` when output is
  suppressed and `RecordingLogger` when tests inspect diagnostics.
- Do not expose a global logger or use `print`. Do not log domain payloads,
  credentials, keys, or raw event data.

## Errors and invariants

- Unless specified explicity, treat `Error` as fatal and let it reach the
  application boundary. Use an `Exception` for validation, rejected commands,
  stale state, and other expected non-fatal outcomes.
- `CommandException` is the conventional CQRS command-rejection type, but
  applications may use another `Exception`.
- Handle an `Exception` only where recovery, reporting, or translation is
  needed. Preserve stack traces when translating, add context narrowly, and do
  not hide unrelated failures.
- Throw `Error` when the implemented systems are misused in consumer. If unsure
  about these boundaries, please ask.
