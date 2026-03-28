class CommandResult {
  final String? nackReason;
  // this cannot be an error. An error is propagated up, never swallowed
  final Exception? exception;

  const CommandResult({required this.nackReason, required this.exception});

  const CommandResult.success() : this(nackReason: null, exception: null);

  const CommandResult.nack({required String reason})
    : this(nackReason: reason, exception: null);

  const CommandResult.exception({required Exception exception})
    : this(nackReason: null, exception: exception);
}
