/// An error raised while pumping events into projections.
typedef CqrsProjectionError = ({Object error, StackTrace stackTrace});

/// Every projection error collected from one failed pump page.
final class CqrsProjectionFailure implements Exception {
  final List<CqrsProjectionError> errors;

  CqrsProjectionFailure(List<CqrsProjectionError> errors)
    : errors = List.unmodifiable(errors) {
    if (errors.isEmpty) {
      throw ArgumentError.value(errors, 'errors', 'must not be empty');
    }
  }

  StackTrace get stackTrace => errors.first.stackTrace;
}
