import 'dart:typed_data';

import 'package:common/common.dart';
import 'package:cqrs/cqrs.dart';

part 'tag_assigned.dart';
part 'tag_created.dart';
part 'tag_removed.dart';
part 'tag_renamed.dart';
part 'tag_unassigned.dart';

sealed class TagEvent {
  const TagEvent();

  Map<String, dynamic> toJson();
}
