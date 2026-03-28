// TODO: this must be split into Clock and IdGenerator
abstract interface class CommandSideEffects {
  DateTime currentTime();
  String newId();
}
