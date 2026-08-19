# Claudare product vision

## Status

This document describes an unimplemented product direction. It is not an
architecture contract, capability statement, or delivery plan. Current,
source-backed behavior is documented in [SUMMARY.md](SUMMARY.md),
[ARCHITECTURE_COMMON.md](ARCHITECTURE_COMMON.md), and
[IMPLEMENTATION.md](IMPLEMENTATION.md).

Today Claudare is a local development prototype. It does not provide
synchronization, peer discovery, device enrollment, authenticated identity,
encryption, blob storage, backup, or replicated convergence.

## Vision

The long-term idea is a family of local-first applications for personal data,
potentially including notes, contacts, calendars, media, and maps. A future
ecosystem may aim for:

- useful offline operation across major mobile and desktop platforms;
- synchronization without requiring one central application server;
- opportunistic local-network communication and resilience to disconnection;
- a shared synchronization protocol across applications;
- end-to-end encrypted data under user-controlled identities and keys;
- optional backup through trusted peers (yourself included!); and
- freely usable applications without feature paywalls.

Each item requires its own product requirements, threat model, protocol design,
implementation, and validation. In particular, local event records and the
planned `TestSyncSystem` are not evidence that production synchronization,
security, backup, or convergence exists. See [SECURITY.md](SECURITY.md) for the
current trust boundary and [IMPROVEMENTS.md](IMPROVEMENTS.md) for prerequisites.
