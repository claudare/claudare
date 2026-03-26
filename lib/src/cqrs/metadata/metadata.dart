// typedef AnyMetadata = Map<String, dynamic>;

/// TODO: remove custom metadata completely. Instead pass in localSequence, version, and occuredAt
abstract class AnyMetadata {
  Map<String, dynamic> toJson();
}
