# Isolate SQLite

Asynchronous SQLite access for persistent data or in-memory databases.

```dart
final database = IsolateSqlite();
await database.openInMemory();
try {
  final value = await database.queryValue<int?>('SELECT NULL');
  final rows = await database.query('SELECT 1 AS id, NULL AS name');
  for (final row in rows) {
    final id = row.field<int>('id');
    final name = row.field<String?>('name');
  }
} finally {
  await database.close();
}
```

Type arguments can be nullable. Use `int?` or `String?` when a query value or
field may be SQL `NULL`. A nullable `queryValue` also returns `null` when no
row is found; a non-nullable type rejects missing or null values.

Use a transaction for writes that must succeed together. The transactions are
syncronous.
