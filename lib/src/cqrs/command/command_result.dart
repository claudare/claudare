class CommandResult {
  final String? nackReason;
  // this cannot be an error. An error is propagated up, never swallowed
  final Exception? exception;

  const CommandResult._({required this.nackReason, required this.exception});

  const CommandResult.success() : this._(nackReason: null, exception: null);

  const CommandResult.nack({required String reason})
    : this._(nackReason: reason, exception: null);

  const CommandResult.exception({required Exception exception})
    : this._(nackReason: null, exception: exception);
}
