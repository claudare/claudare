# Support directory

Manage files in the platform application support directory.

```dart
final support = PathProviderSupportDirectory();
final directory = await support.getDirectory();
final databasePath = await support.getFilePath('main.sqlite');
```

Close resources using the directory before calling `support.delete()`. This
deletes the entire application support directory and its contents.

Use an isolated temporary directory in tests and register cleanup before
registering resource teardown, so resources close first:

```dart
final support = TempSupportDirectory();
addTearDown(support.delete);
final databasePath = await support.getFilePath('main.sqlite');
```
