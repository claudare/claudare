# Notes

Notes is a Flutter prototype for local event-sourced notes. It creates, edits,
trashes, and restores notes. Note queries support active and trashed filtering
and chronological sorting. Settings shows active-note and event counts and can
reset local event history after confirmation. Reset requires a fresh launch.

The application stores note events in `events.sqlite`. Note details and lists
are rebuilt from that history when queried. It does not provide text search,
replication, encryption, or backup.

## Run

From the workspace root, resolve dependencies with `fvm flutter pub get`.
Then run `fvm flutter run` from `apps/notes`.
