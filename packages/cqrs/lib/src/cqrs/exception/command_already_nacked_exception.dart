class CommandAlreadyNackedException implements Exception {
  const CommandAlreadyNackedException();

  @override
  String toString() => 'CommandAlreadyNackedException';
}
