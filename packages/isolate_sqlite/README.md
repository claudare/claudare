# Isolate SQLite

Asynchronous SQLite access for persistent data or in-memory databases.

```dart
final database = IsolateSqlite();
await database.openInMemory();
try {
  await database.queryValue<int>('SELECT 1');
} finally {
  await database.close();
}
```

Use a transaction for writes that must succeed together. Database callbacks must
be synchronous. Close the database after all consumers have finished.
