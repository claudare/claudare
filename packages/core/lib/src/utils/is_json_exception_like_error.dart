/// JSON decoding can surface these runtime errors for malformed data.
bool isJsonExceptionLikeError(Object error) {
  return error is TypeError ||
      error is NoSuchMethodError ||
      error is RangeError;
}
