part of 'crdt_text.dart';

/// A minimal adapter boundary for a text editor such as TextEditingController.
///
/// Assigning [value] must update text and editing state together and notify
/// listeners synchronously. The adapter owns translation to framework types.
abstract interface class CrdtTextController {
  TextEditingValue get value;
  set value(TextEditingValue value);

  void addListener(void Function() listener);
  void removeListener(void Function() listener);
}
