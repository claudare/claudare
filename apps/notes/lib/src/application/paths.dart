import 'package:cqrs/cqrs.dart';

String noteStream(String noteId) => 'note/$noteId';

/// Returns the note ID or throws [FormatException] for an invalid stream path.
String noteIdFromStream(String streamPath) {
  const prefix = 'note/';
  if (!streamPath.startsWith(prefix) || streamPath.length == prefix.length) {
    throw const FormatException('Invalid note stream path');
  }
  return streamPath.substring(prefix.length);
}

LogFilter noteStreamFilter(String noteId) => LogFilter.exact('note/$noteId');

final allNotesFilter = LogFilter.startsWith('note/');
