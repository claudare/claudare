import 'dart:async';
import 'dart:convert';

import 'package:stream_channel/stream_channel.dart';
import 'package:test/test.dart';
import 'package:transport/transport.dart';

Future<void> flush() => Future<void>.delayed(Duration.zero);

String frame(String protocol, String data, {int generation = 0}) => jsonEncode({
  'protocol': protocol,
  'type': 'data',
  'generation': generation,
  'data': data,
});

void main() {
  test('custom protocols reset independently over one connection', () async {
    final wire = StreamChannelController<String>();
    final left = PeerMultiplexer(wire.local);
    final right = PeerMultiplexer(wire.foreign);
    const names = ['chat', 'presence', 'files'];
    final channels = {for (final name in names) name: right.channel(name)};
    for (final name in names) {
      left.channel(name);
    }
    await left.channel('presence').sink.close();
    await flush();
    expect(right.channel('presence'), isNot(same(channels['presence'])));
    for (final name in ['chat', 'files']) {
      expect(right.channel(name), same(channels[name]));
    }
    final received = {
      for (final name in names) name: right.channel(name).stream.toList(),
    };
    for (final name in names) {
      left.channel(name).sink.add(name);
    }
    await flush();
    await left.close();
    for (final name in names) {
      expect(await received[name], [name]);
    }
    await right.close();
  });

  for (final sessionsFirst in [false, true]) {
    test(
      'registration is reused with sessions first: $sessionsFirst',
      () async {
        final wire = StreamChannelController<String>();
        final mux = PeerMultiplexer(wire.local);
        wire.foreign.stream.listen(null);
        if (sessionsFirst) mux.sessions('custom');
        final channel = mux.channel('custom');
        final sessions = mux.sessions('custom');
        expect(mux.channel('custom'), same(channel));
        expect(mux.sessions('custom'), sessions);
        await mux.close();
        expect(mux.channel('custom'), same(channel));
        expect(mux.sessions('custom'), sessions);
        expect(await sessions.toList(), [channel]);
        expect(await channel.stream.toList(), isEmpty);
      },
    );
  }

  for (final name in ['', ' \t\n']) {
    test('blank name ${jsonEncode(name)} is rejected', () async {
      final wire = StreamChannelController<String>();
      final mux = PeerMultiplexer(wire.local);
      wire.foreign.stream.listen(null);
      expect(() => mux.channel(name), throwsArgumentError);
      expect(() => mux.sessions(name), throwsArgumentError);
      await mux.close();
    });
  }

  test('new registrations after closure are rejected', () async {
    final wire = StreamChannelController<String>();
    final mux = PeerMultiplexer(wire.local);
    wire.foreign.stream.listen(null);
    await mux.close();
    expect(() => mux.channel('new'), throwsStateError);
    expect(() => mux.sessions('new'), throwsStateError);
  });

  test(
    'unregistered data and resets are discarded before registration',
    () async {
      final wire = StreamChannelController<String>();
      final mux = PeerMultiplexer(wire.local);
      wire.foreign.stream.listen(null);
      wire.foreign.sink.add(frame('custom', 'discarded'));
      wire.foreign.sink.add(
        jsonEncode({'protocol': 'custom', 'type': 'reset', 'generation': 5}),
      );
      await flush();
      final channel = mux.channel('custom');
      final received = channel.stream.toList();
      wire.foreign.sink.add(frame('custom', 'delivered'));
      await flush();
      await mux.close();
      expect(await received, ['delivered']);
      expect(await mux.sessions('custom').toList(), [channel]);
    },
  );

  test(
    'interleaved payloads retain exact content and order both ways',
    () async {
      final wire = StreamChannelController<String>();
      final first = PeerMultiplexer(wire.local);
      final second = PeerMultiplexer(wire.foreign);
      final received = [<String>[], <String>[], <String>[], <String>[]];
      final channels = [
        first.channel('commands'),
        first.channel('blobs'),
        second.channel('commands'),
        second.channel('blobs'),
      ];
      for (var i = 0; i < channels.length; i++) {
        channels[i].stream.listen(received[i].add);
      }
      const payloads = ['', '"quoted"\n雪', '{"data":"unchanged"}'];
      for (final payload in payloads) {
        first.channel('commands').sink.add(payload);
        second.channel('blobs').sink.add(payload);
        first.channel('blobs').sink.add(payload);
        second.channel('commands').sink.add(payload);
      }
      await flush();
      for (final values in received) {
        expect(values, payloads);
      }
      await first.close();
      await second.close();
    },
  );

  test('buffers each channel until its delayed subscription', () async {
    final wire = StreamChannelController<String>();
    final mux = PeerMultiplexer(wire.local);
    wire.foreign.stream.listen(null);
    for (final protocol in ['commands', 'blobs']) {
      mux.channel(protocol);
      for (final data in ['first', 'second']) {
        wire.foreign.sink.add(frame(protocol, data));
      }
    }
    await flush();
    await mux.close();
    expect(await mux.channel('commands').stream.toList(), ['first', 'second']);
    expect(await mux.channel('blobs').stream.toList(), ['first', 'second']);
  });

  for (final pausedProtocol in ['commands', 'blobs']) {
    test('pausing $pausedProtocol does not pause the other channel', () async {
      final wire = StreamChannelController<String>();
      final mux = PeerMultiplexer(wire.local);
      wire.foreign.stream.listen(null);
      final commands = <String>[];
      final blobs = <String>[];
      final commandSub = mux.channel('commands').stream.listen(commands.add);
      final blobSub = mux.channel('blobs').stream.listen(blobs.add);
      final paused = pausedProtocol == 'commands' ? commandSub : blobSub;
      paused.pause();
      for (final protocol in ['commands', 'blobs']) {
        wire.foreign.sink.add(frame(protocol, 'data'));
      }
      await flush();
      expect(pausedProtocol == 'commands' ? commands : blobs, isEmpty);
      expect(pausedProtocol == 'commands' ? blobs : commands, ['data']);
      paused.resume();
      await flush();
      expect(commands, ['data']);
      expect(blobs, ['data']);
      await mux.close();
    });
  }

  for (final protocol in ['commands', 'blobs']) {
    test(
      'closing $protocol replaces only that protocol on both peers',
      () async {
        final wire = StreamChannelController<String>();
        final left = PeerMultiplexer(wire.local);
        final right = PeerMultiplexer(wire.foreign);
        final old = protocol == 'commands'
            ? left.channel('commands')
            : left.channel('blobs');
        final remoteOld = protocol == 'commands'
            ? right.channel('commands')
            : right.channel('blobs');
        final other = protocol == 'commands'
            ? left.channel('blobs')
            : left.channel('commands');
        final remoteOther = protocol == 'commands'
            ? right.channel('blobs')
            : right.channel('commands');
        final received = <String>[];
        remoteOther.stream.listen(received.add);
        await old.sink.close();
        await flush();
        await remoteOld.sink.done;
        final replacement = protocol == 'commands'
            ? left.channel('commands')
            : left.channel('blobs');
        final remoteReplacement = protocol == 'commands'
            ? right.channel('commands')
            : right.channel('blobs');
        expect(replacement, isNot(same(old)));
        expect(remoteReplacement, isNot(same(remoteOld)));
        expect(
          protocol == 'commands'
              ? left.channel('blobs')
              : left.channel('commands'),
          same(other),
        );
        other.sink.add('uninterrupted');
        final restarted = <String>[];
        remoteReplacement.stream.listen(restarted.add);
        replacement.sink.add('restarted');
        await flush();
        expect(received, ['uninterrupted']);
        expect(restarted, ['restarted']);
        expect(() => old.sink.add('late'), throwsStateError);
        await old.sink.close();
        expect(
          protocol == 'commands'
              ? left.channel('commands')
              : left.channel('blobs'),
          same(replacement),
        );
        await left.close();
        await right.close();
      },
    );
  }

  test('simultaneous resets converge on one replacement session', () async {
    final wire = StreamChannelController<String>();
    final left = PeerMultiplexer(wire.local);
    final right = PeerMultiplexer(wire.foreign);
    final leftSessions = <StreamChannel<String>>[];
    final rightSessions = <StreamChannel<String>>[];
    left.sessions('commands').listen(leftSessions.add);
    right.sessions('commands').listen(rightSessions.add);
    final leftClosing = left.channel('commands').sink.close();
    final rightClosing = right.channel('commands').sink.close();
    await Future.wait([leftClosing, rightClosing]);
    await flush();
    expect(leftSessions, hasLength(2));
    expect(rightSessions, hasLength(2));
    final received = <String>[];
    right.channel('commands').stream.listen(received.add);
    left.channel('commands').sink.add('new session');
    await flush();
    expect(received, ['new session']);
    await left.close();
    await right.close();
  });

  test(
    'stale payloads and reset markers cannot affect a replacement',
    () async {
      final wire = StreamChannelController<String>();
      final mux = PeerMultiplexer(wire.local);
      wire.foreign.stream.listen(null);
      await mux.channel('commands').sink.close();
      final replacement = mux.channel('commands');
      final received = <String>[];
      replacement.stream.listen(received.add);
      wire.foreign.sink.add(frame('commands', 'stale'));
      wire.foreign.sink.add(
        jsonEncode({'protocol': 'commands', 'type': 'reset', 'generation': 0}),
      );
      wire.foreign.sink.add(
        jsonEncode({'protocol': 'commands', 'type': 'reset', 'generation': 1}),
      );
      wire.foreign.sink.add(frame('commands', 'current', generation: 1));
      await flush();
      expect(mux.channel('commands'), same(replacement));
      expect(received, ['current']);
      await mux.close();
    },
  );

  for (final protocol in ['commands', 'blobs']) {
    test('a $protocol sink error leaves the other protocol running', () async {
      final wire = StreamChannelController<String>();
      final left = PeerMultiplexer(wire.local);
      final right = PeerMultiplexer(wire.foreign);
      final failed = protocol == 'commands'
          ? left.channel('commands')
          : left.channel('blobs');
      final other = protocol == 'commands'
          ? left.channel('blobs')
          : left.channel('commands');
      final remoteOther = protocol == 'commands'
          ? right.channel('blobs')
          : right.channel('commands');
      final failure = Exception('failed');
      final errors = expectLater(
        failed.stream,
        emitsInOrder([emitsError(same(failure)), emitsDone]),
      );
      final received = <String>[];
      remoteOther.stream.listen(received.add);
      failed.sink.addError(failure);
      other.sink.add('still running');
      await errors;
      await flush();
      expect(received, ['still running']);
      expect(
        protocol == 'commands'
            ? right.channel('blobs')
            : right.channel('commands'),
        same(remoteOther),
      );
      await left.close();
      await right.close();
    });
  }

  test('replacement sessions buffer until their consumer starts', () async {
    final wire = StreamChannelController<String>();
    final left = PeerMultiplexer(wire.local);
    final right = PeerMultiplexer(wire.foreign);
    right.sessions('commands');
    await left.channel('commands').sink.close();
    left.channel('commands').sink.add('first');
    left.channel('commands').sink.add('second');
    await flush();
    await left.close();
    final sessions = await right.sessions('commands').toList();
    expect(sessions, hasLength(2));
    expect(await sessions.last.stream.toList(), ['first', 'second']);
    await right.close();
  });

  test('cleanup completes with an unused blob channel', () async {
    final wire = StreamChannelController<String>();
    final mux = PeerMultiplexer(wire.local);
    mux.channel('blobs');
    wire.foreign.stream.listen(null);
    mux.channel('commands').stream.listen(null);
    await mux
        .channel('commands')
        .sink
        .close()
        .timeout(const Duration(seconds: 1));
    await mux.close();
    expect(await mux.channel('blobs').stream.toList(), isEmpty);
  });

  test('cancelling a consumer restarts only its protocol', () async {
    final wire = StreamChannelController<String>();
    final mux = PeerMultiplexer(wire.local);
    wire.foreign.stream.listen(null);
    final commands = mux.channel('commands');
    final blobs = mux.channel('blobs');
    await commands.stream.listen(null).cancel();
    expect(mux.channel('commands'), isNot(same(commands)));
    expect(mux.channel('blobs'), same(blobs));
    await mux.close();
  });

  test(
    'addStream routes payloads while the other sink remains writable',
    () async {
      final wire = StreamChannelController<String>();
      final mux = PeerMultiplexer(wire.local);
      final frames = <String>[];
      wire.foreign.stream.listen(frames.add);
      final source = StreamController<String>();
      final adding = mux.channel('commands').sink.addStream(source.stream);
      source.add('command');
      mux.channel('blobs').sink.add('blob');
      await source.close();
      await adding;
      await flush();
      expect(
        frames.map(jsonDecode),
        unorderedEquals([
          jsonDecode(frame('commands', 'command')),
          jsonDecode(frame('blobs', 'blob')),
        ]),
      );
      await mux.close();
    },
  );

  test('shared shutdown cancels an ongoing addStream', () async {
    final wire = StreamChannelController<String>();
    final mux = PeerMultiplexer(wire.local);
    wire.foreign.stream.listen(null);
    var cancelled = false;
    final source = StreamController<String>(onCancel: () => cancelled = true);
    final adding = mux.channel('commands').sink.addStream(source.stream);
    await mux.close();
    await adding;
    expect(cancelled, isTrue);
    await source.close();
  });

  test('transport closure ends both channels', () async {
    final wire = StreamChannelController<String>();
    final mux = PeerMultiplexer(wire.local);
    wire.foreign.stream.listen(null);
    final commands = mux.channel('commands').stream.toList();
    final blobs = mux.channel('blobs').stream.toList();
    await wire.foreign.sink.close();
    expect(await commands, isEmpty);
    expect(await blobs, isEmpty);
    await mux.close();
  });

  test('transport errors fail both channels and close the peer', () async {
    final wire = StreamChannelController<String>();
    final mux = PeerMultiplexer(wire.local);
    final remoteDone = wire.foreign.stream.drain<void>();
    final error = Exception('transport failed');
    final commands = expectLater(
      mux.channel('commands').stream,
      emitsInOrder([emitsError(same(error)), emitsDone]),
    );
    final blobs = expectLater(
      mux.channel('blobs').stream,
      emitsInOrder([emitsError(same(error)), emitsDone]),
    );
    wire.foreign.sink.addError(error);
    await Future.wait([commands, blobs, remoteDone]);
  });

  for (final message in [
    '{',
    '[]',
    '{}',
    '{"protocol":"other","data":"x"}',
    '{"protocol":"commands","type":"data","generation":0,"data":1}',
    '{"protocol":"commands","type":"reset","generation":-1}',
  ]) {
    test('malformed envelope $message is discarded', () async {
      final wire = StreamChannelController<String>();
      final mux = PeerMultiplexer(wire.local);
      wire.foreign.stream.listen(null);
      final commands = mux.channel('commands');
      final blobs = mux.channel('blobs');
      final received = <String>[];
      commands.stream.listen(received.add);
      wire.foreign.sink.add(message);
      wire.foreign.sink.add(frame('commands', 'valid'));
      await flush();
      expect(mux.channel('commands'), same(commands));
      expect(mux.channel('blobs'), same(blobs));
      expect(received, ['valid']);
      await mux.close();
    });
  }
}
