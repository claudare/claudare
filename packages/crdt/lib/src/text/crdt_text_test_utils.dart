part of 'crdt_text.dart';

CrdtTextChange? testCrdtTextApplyChangeToDocument(
  CrdtText document,
  String value, {
  String actorId = 'a',
}) {
  final context = CrdtTextEditContext(actorId: actorId, document: document);
  updateText(context, value);
  final change = context.prepareChange();
  if (change != null) {
    context.acknowledgeChange(change);
  }
  return change;
}

CrdtTextChange testCrdtTextSingleChange(String value, {String actorId = 'a'}) {
  final document = CrdtText();
  final change = testCrdtTextApplyChangeToDocument(
    document,
    value,
    actorId: actorId,
  );
  return change!;
}
