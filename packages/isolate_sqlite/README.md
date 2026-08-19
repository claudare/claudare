TODO: Put a short description of the package here that helps potential users
know whether this package might be useful for them.

## Features

TODO: List what your package can do. Maybe include images, gifs, or videos.

## Getting started

TODO: List prerequisites and provide or point to information on how to
start using the package.

## Usage

Open an in-memory database with the convenience method:

```dart
final database = IsolateSqlite();
await database.openInMemory();
```

Code that supplies database filenames can use the public memory filename:

```dart
await database.open(IsolateSqlite.memoryFilename);
```

## Additional information

TODO: Tell users more about the package: where to find more information, how to 
contribute to the package, how to file issues, what response they can expect 
from the package authors, and more.
