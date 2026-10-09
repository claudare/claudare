# KV

Store small string and boolean values, such as application preferences. Use
memory storage for temporary values or SQLite for persistence.

```dart
final preferences = MemoryKv();
await preferences.setBool('sync.enabled', false);
final enabled = await preferences.getBool('sync.enabled');
```

For SQLite, open the database and migrate the store before use. Closing the
store also closes its supplied database, so finish using shared consumers first.
