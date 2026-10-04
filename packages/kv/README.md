# KV store

`kv` owns string key-value persistence through `Kv` and `SqliteKv`. SQLite is
the only backing storage. Missing keys return null, writes replace existing
values, batch writes are atomic, and key listing matches literal key prefixes.
`getString` and `setString` access stored strings. Conversion helpers support
strings and booleans through `getBool`, `setBool`, `getTyped`, and `setTyped`.
`setAllStrings` accepts a string map; `setAll` accepts a mixed string and boolean
map and rejects unsupported values before writing. `listKeys` returns sorted
keys without their values.

Open an `IsolateSqlite`, inject it into `SqliteKv`, and call `migrate()` before
use. Its schema and migration history are namespaced so other stores can share
the database. The application owns the shared connection's lifetime;
`SqliteKv.close()` closes that connection.

`KvTestHelper.createMemoryKv()` creates a migrated store using in-memory
SQLite. Callers must close it after use.

This package provides local persistence without encryption or synchronization.
