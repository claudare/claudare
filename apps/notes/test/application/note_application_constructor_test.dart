import 'package:claudare_logging/claudare_logging.dart';
import 'package:id_generator/id_generator.dart';
import 'package:notes/application/note_application.dart';
import 'package:test/test.dart';
import 'package:time_provider/time_provider.dart';

void main() {
  test('test constructor uses test defaults', () {
    final application = NoteApplication.test();
    addTearDown(application.close);

    expect(application.idGenerator, isA<IdGeneratorSequential>());
    expect(application.timeProvider, isA<FakeTimeProviderStatic>());
    expect(
      application.timeProvider.now(),
      DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
    );
    expect(application.logger, isA<NoopLogger>());
  });

  test('test constructor uses supplied collaborators', () {
    final idGenerator = IdGeneratorSequential();
    final timeProvider = FakeTimeProviderStatic.zero();
    final logger = RecordingLogger();

    final application = NoteApplication.test(
      idGenerator: idGenerator,
      timeProvider: timeProvider,
      logger: logger,
    );
    addTearDown(application.close);

    expect(application.idGenerator, same(idGenerator));
    expect(application.timeProvider, same(timeProvider));
    expect(application.logger, same(logger));
  });
}
