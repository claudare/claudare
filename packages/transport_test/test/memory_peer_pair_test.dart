import 'dart:async';

import 'package:test/test.dart';
import 'package:transport_test/transport_test.dart';

void main() {
  test('pair assigns remote actors and exchanges ordered messages', () async {
    final pair = createMemoryPeerPair(
      firstActor: 'first',
      secondActor: 'second',
    );
    final firstMessages = <String>[];
    final secondMessages = <String>[];
    pair.first.channel.stream.listen(firstMessages.add);
    pair.second.channel.stream.listen(secondMessages.add);

    pair.first.channel.sink.add('one');
    pair.first.channel.sink.add('two');
    pair.second.channel.sink.add('three');
    await _flush();

    expect(pair.first.actor, 'second');
    expect(pair.second.actor, 'first');
    expect(firstMessages, ['three']);
    expect(secondMessages, ['one', 'two']);
  });

  test('closing one endpoint closes both directions', () async {
    final pair = createMemoryPeerPair(
      firstActor: 'first',
      secondActor: 'second',
    );
    final firstDone = Completer<void>();
    final secondDone = Completer<void>();
    pair.first.channel.stream.listen(null, onDone: firstDone.complete);
    pair.second.channel.stream.listen(null, onDone: secondDone.complete);

    await pair.first.channel.sink.close();

    await Future.wait([firstDone.future, secondDone.future]);
    await pair.second.channel.sink.done;
  });
}

Future<void> _flush() => Future<void>.delayed(Duration.zero);
