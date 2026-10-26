# Sync

CQRS command replication. Use a coordinator for background operation, or
combine a transport and replicator directly when the application needs to
control them.

Use the `transport` package for peer connections and multiplexing. Injected
stores remain caller-owned, and connection status does not indicate
synchronization progress.

To use blobs, inject them as a dependency in the command hanlders.

This is not a complete synchronization system. Authentication, identity
verification, and encryption are not provided.
