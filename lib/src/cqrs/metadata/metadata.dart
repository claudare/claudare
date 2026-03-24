// typedef AnyMetadata = Map<String, dynamic>;

/// TODO: maybe just keep it as a map and let whoever want to use it (probably not)
/// to deal with that type complexity
abstract class AnyMetadata {
  Map<String, dynamic> toJson();
}
