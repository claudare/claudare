# Notes

Notes is a Flutter prototype for local event-sourced notes. Its note behavior
lives in the [Dart Notes core](../../apps/notes/README.md). It creates, edits,
trashes, and restores notes. Note queries support active and trashed filtering
and chronological sorting.

On first launch, ActorSetup chooses a local public key. SyncSetup lets users
enable sync by configuring a replication server URL and a string group,
defaulting to `"0"`, or skip server setup. The saved `sync.enabled` choice
controls whether server configuration is required, even when a URL and group
are already stored. Completed steps are preserved across restarts. Actor
identity, peer pairings, sync configuration, and note events share
`main.sqlite`. Resetting the database clears them all. The configured server
is not contacted yet.

New events use the local public key as their actor identity. Note details and
lists are rebuilt from that history when queried. It does not provide text
search, replication, encryption, or backup.

Content editing uses CRDT changes with focus-loss and navigation saves. Ctrl+S
saves the open note and reports when there are no changes. Refresh merges
persisted edits into an open draft. For visual testing, the simulation toggle
inserts external text at a random position every five seconds. The editor
refreshes when the event store reports a change to the open note.
