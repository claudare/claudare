class CommandAlreadyNackedException implements Exception {
  CommandAlreadyNackedException();

  @override
  String toString() => 'CommandAlreadyNackedException';
}
