class CommandNack implements Exception {
  final String message;

  CommandNack({required this.message});

  @override
  String toString() => 'CommandNack: $message';
}
