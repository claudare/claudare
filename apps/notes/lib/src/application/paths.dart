import 'package:cqrs/cqrs.dart';

String noteStream(String noteId) => 'note/$noteId';

PatternFilter noteStreamFilter(String noteId) =>
    PatternFilter.exact('note/$noteId');

final allNotesFilter = PatternFilter.startsWith('note/');
