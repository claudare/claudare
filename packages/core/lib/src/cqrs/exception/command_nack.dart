class CommandNack implements Exception {
  final String message;

  const CommandNack({required this.message});

  @override
  String toString() => 'CommandNack: $message';
}
