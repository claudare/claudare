# Sync

Development primitives for peer communication and experimental CQRS command
replication. Use a coordinator for background operation, or combine transports
and replicators directly when the application needs to control them.

Use in-memory connections for local experiments and proxy-backed connections for
remote peers. Subscribe to peer discovery before starting a transport. Injected
stores remain caller-owned, and connection status does not indicate
synchronization progress.

This is not a complete synchronization system. Authentication, identity
verification, and encryption are not provided.
