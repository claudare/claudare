import 'package:flutter/foundation.dart';

final class ReadModelNotifier extends ChangeNotifier {
  void notifyChanged() => notifyListeners();
}
