# Claudare security posture

## Current classification

The reusable core is a local CQRS foundation, not a security or synchronization
framework. It has no cryptographic primitives, device identity, membership
model, transport, event import/export, blob subsystem, or backup system. Do
not make confidentiality, integrity, multi-device, or recovery claims for core.

## Data at rest

`core` stores encoded command and event payloads through an application-selected
event store. Encoding is neither confidentiality nor authentication. Its local,
stream, device, and causal sequence fields are not signed identities,
deduplication guarantees, or replay defenses.

## Identity and multi-device boundary

There is no device enrollment, key pair, membership state, revocation, recovery,
or trusted device registry. SQLite sequence values are local counters, not
secure author identity. There is no event import/export or transport path.

## Sensitive diagnostics

`claudare_logging` supplies the explicit logging boundary. Packages and
applications must not emit domain payloads, credentials, database paths, keys,
or raw event data through `print` or a logger.

## Required gates before security claims

Before enabling synchronization or claiming confidentiality, implement and
review a threat model; authenticated enrollment/membership/removal/recovery;
a versioned event envelope with identity, idempotence, and replay handling;
deterministic replicated conflict rules; at-rest key custody; bounded
authenticated parsing; an independently reviewed cryptographic protocol; and
an authenticated backup inventory with a clean-device restore drill.

Until those gates have implemented code and adversarial tests, Claudare is a
local development prototype only.
