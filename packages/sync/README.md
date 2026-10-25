# Sync

CQRS command and blob replication. Use a coordinator for
background operation, or combine a transport and replicators directly when the
application needs to control them.

Use the `transport` package for peer connections and multiplexing. Injected
stores remain caller-owned, and connection status does not indicate
synchronization progress.

For blob experiments, share one blob store between the CQRS runtime and its
coordinator. Applications must handle missing blob data while it is replicating.

This is not a complete synchronization system. Authentication, identity
verification, and encryption are not provided.
