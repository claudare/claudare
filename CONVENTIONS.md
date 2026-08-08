# Core wiring conventions

## Scope

Core is Claudare's reusable, application-independent logical layer. It spans
`packages/core`, `packages/isolate_sqlite`, and `packages/claudare_logging` as
needed. `apps/notes` is a prototype consumer that exercises the layer; it does
not define Core's architecture or public API for future applications.

These conventions apply to new and modified code. Existing deviations are
context for future work, not a refactoring requirement by themselves.

## Contracts and implementations

Public package entrypoints are consumer boundaries. Applications and other
packages import Core's exported libraries, not `src` internals. Core
implementation and white-box tests may use internals where that is necessary.

Design contracts as small, composable capabilities. Aggregate interfaces
compose those capabilities without exposing concrete storage or runtime
details.

Use constructor injection for storage, time, IDs, logging, and similar
collaborators. Name production, in-memory, and deterministic test substitutes
by role, such as `Memory`, `Fake`, `System`, `Random`, `Seeded`, and
`Sequential`.

In-memory implementations are the authoritative behavior references. Every
side-effecting implementation, including SQLite, must match them. Add parity
or table-driven tests when an interface has multiple implementations or a
behavioral edge case would otherwise be easy to diverge.

Prefer `abstract interface class` for contracts. Name a contract for its
domain, without an added `Repository`, `Service`, `Implementation`, or similar
suffix. Prefix a concrete type with that domain name, such as `MemoryEventStore`.

Prefer one class per file. Related interface types may share a file, as may a
cohesive domain group such as CQRS events. Put implementations in nested
folders when that clarifies ownership, or keep a flat layout when it is simpler.

Use `*_safe.dart` wrappers for assertions and exception translation. Keep
package exceptions in a shared exception folder rather than distributing them
among feature files.

## Errors and invariants

Catch `Exception` values when recovery or translation is needed. Let `Error`
values propagate, preserving their debugging signal. Preserve stack traces
when translating exceptions. Narrow handling for known encoding or decoding
errors is allowed when it adds useful context without hiding unrelated faults.

Use assertions for defensive invariants.

## Writing and UI

Avoid em-dashes and unnecessary comments in code. Never use an em-dash in
code comments or user-facing text. Do not add extra descriptive or help
messages when implementing a UI feature unless asked. Do not use strong or
expressive language that has no meaning.
