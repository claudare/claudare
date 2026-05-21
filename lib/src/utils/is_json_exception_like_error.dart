// these errors can happen when json is cast to objects
// the application should not crash!
bool isJsonExceptionLikeError(Object error) {
  return error is TypeError ||
      error is NoSuchMethodError ||
      error is RangeError;
}
