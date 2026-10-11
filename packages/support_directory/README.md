# Support directory

Use a namespace to keep application data for different environments separate.

```dart
final support = SupportDirectory(namespace: 'dev');
final directory = await support.getDirectory();
final databasePath = await support.getFilePath('main.sqlite');
```

Close resources using the directory before calling `support.delete()` to reset
that namespace. Other namespaces are preserved.

Use an isolated temporary directory in tests and register cleanup before
registering resource teardown, so resources close first:

```dart
final support = TempSupportDirectory();
addTearDown(support.delete);
final databasePath = await support.getFilePath('main.sqlite');
```
