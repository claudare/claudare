# Transport Test

In-memory transport utilities for deterministic tests.

Create transports through one `MemoryTransportNetwork` to give them a shared
discovery domain. Use `createMemoryPeerPair` when a test needs two connected
peer channels without transport discovery.
