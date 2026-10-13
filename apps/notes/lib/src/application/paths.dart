import 'package:cqrs/cqrs.dart';

String noteStream(String noteId) => 'note/$noteId';

LogFilter noteStreamFilter(String noteId) => LogFilter.exact('note/$noteId');

final allNotesFilter = LogFilter.startsWith('note/');
