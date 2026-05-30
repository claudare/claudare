import 'crdt_text_change.dart';

// this is how loading and unloading is done
abstract interface class CrdtTextRepository {
  /// this should proxy writing to an event stream
  Future<void> storeChange(CrdtTextChange change);

  /// loading should be performed from the projection
  /// what if projection applies changes itself and stores the resolved table
  /// instead?
  Future<List<CrdtTextChange>> loadAllChanges();
}
