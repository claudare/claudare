import 'dart:async';

import 'package:cqrs/src/cqrs/command/command.dart';
import 'package:cqrs/src/cqrs/command/command_executor.dart';
import 'package:cqrs/src/cqrs/command/command_input.dart';
import 'package:cqrs/src/cqrs/cqrs_runtime/cqrs_runtime_dependencies.dart';
import 'package:cqrs/src/cqrs/cqrs_runtime/cqrs_runtime_lifecycle.dart';
import 'package:cqrs/src/cqrs/cqrs_runtime/event_pump.dart';
import 'package:cqrs/src/cqrs/event/event_registry.dart';
import 'package:cqrs/src/cqrs/event_store/event_store.dart';
import 'package:cqrs/src/cqrs/exception/cqrs_runtime_failure.dart';
import 'package:cqrs/src/cqrs/projection/projection_registry.dart';
import 'package:cqrs/src/cqrs/runtime_store/runtime_store.dart';
import 'package:time_provider/time_provider.dart';

/// Coordinates durable command execution and projection delivery.
final class CqrsRuntime {
  final String runtimeName;
  final EventStore eventStore;
  final CqrsRuntimeDependencies _dependencies;
  final EventRegistry _eventRegistry;
  final ProjectionRegistry _projectionRegistry;
  final CqrsRuntimeLifecycle _lifecycle = CqrsRuntimeLifecycle();

  late final RuntimeStore _runtimeStore;
  late final CommandExecutor _commandExecutor;
  EventPump? _eventPump;
  StreamSubscription<void>? _appliedChangesSubscription;
  Future<void> _exclusiveWork = Future<void>.value();
  Future<void>? _scheduledPump;
  bool _pumpStarted = false;

  CqrsRuntime({
    required CqrsRuntimeDependencies dependencies,
    required EventRegistry eventRegistry,
    required ProjectionRegistry projectionRegistry,
    required this.runtimeName,
  }) : eventStore = EventStore(dependencies.eventDatabase),
       _dependencies = dependencies,
       _eventRegistry = eventRegistry,
       _projectionRegistry = projectionRegistry {
    _runtimeStore = RuntimeStore(dependencies.runtimeDatabase);
    _commandExecutor = CommandExecutor(
      eventStore: eventStore,
      timeProvider: dependencies.timeProvider,
      eventRegistry: _eventRegistry,
      logger: dependencies.logger,
    );
  }

  TimeProvider get timeProvider => _dependencies.timeProvider;
  CqrsRuntimeFailure? get failure => _lifecycle.failure;
  Stream<CqrsRuntimeFailure> get failures => _lifecycle.failures;

  Future<void> initialize() {
    _lifecycle.beginInitialization();
    _eventRegistry.freeze();
    _projectionRegistry.freeze();
    return _initialize();
  }

  Future<void> _initialize() async {
    try {
      await eventStore.migrate();
      await _runtimeStore.initialize();
      _eventPump = EventPump(
        createReader: eventStore.getAppliedEventReader,
        eventRegistry: _eventRegistry,
        projections: await _projectionRegistry.prepare(
          _runtimeStore,
          forceReset: false,
        ),
      );
      _appliedChangesSubscription = eventStore.appliedChanges.listen(
        (_) => _handleAppliedChanges(),
      );
      _lifecycle.beginInitialRebuild();
      await _pumpEventPump(_eventPump!);
      _lifecycle.completeRebuilding();
    } catch (error, stackTrace) {
      _lifecycle.beginInitializationFailureTeardown();
      await _teardown();
      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  Future<void> execute<Input extends CommandInput>(
    Command<Input> command,
    Input input,
  ) {
    final unavailable = _lifecycle.admitWork('execute commands');
    if (unavailable != null) {
      return Future<void>.error(unavailable, unavailable.stackTrace);
    }

    return _commandExecutor.execute(command, input);
  }

  // TODO: rework me greatly
  Future<void> pump() {
    final unavailable = _lifecycle.admitWork('pump projections');
    if (unavailable != null) {
      return Future<void>.error(unavailable, unavailable.stackTrace);
    }

    final scheduled = _scheduledPump;
    if (scheduled != null) {
      if (_pumpStarted) {
        final wakeup = _pumpEventPump(_eventPump!);
        unawaited(
          wakeup.then<void>((_) {}, onError: (Object _, StackTrace _) {}),
        );
      }
      return scheduled;
    }

    late final Future<void> result;
    result = _enqueueExclusive(() async {
      _pumpStarted = true;
      try {
        await _pumpEventPump(_eventPump!);
      } finally {
        _pumpStarted = false;
      }
    });
    _scheduledPump = result;
    result.then<void>(
      (_) {
        if (identical(_scheduledPump, result)) _scheduledPump = null;
      },
      onError: (Object _, StackTrace _) {
        if (identical(_scheduledPump, result)) _scheduledPump = null;
      },
    );
    return result;
  }

  Future<void> recreateProjections() {
    final unavailable = _lifecycle.admitWork('recreate projections');
    if (unavailable != null) {
      return Future<void>.error(unavailable, unavailable.stackTrace);
    }

    _lifecycle.beginRebuilding();
    return _recreateProjections();
  }

  Future<void> _recreateProjections() async {
    try {
      await _enqueueExclusive(() async {
        _dependencies.logger.info(
          'runtime $runtimeName: recreating all projections',
        );
        _eventPump = EventPump(
          createReader: eventStore.getAppliedEventReader,
          eventRegistry: _eventRegistry,
          projections: await _projectionRegistry.prepare(
            _runtimeStore,
            forceReset: true,
          ),
        );
        await _pumpEventPump(_eventPump!);
        _dependencies.logger.info(
          'runtime $runtimeName: recreated all projections',
        );
      });
    } finally {
      _lifecycle.completeRebuilding();
    }
  }

  void _handleAppliedChanges() {
    if (!_lifecycle.isRunning) return;
    final result = pump();
    unawaited(_containSignalFailure(result));
  }

  Future<void> _containSignalFailure(Future<void> result) async {
    try {
      await result;
    } catch (_) {
      // The public failure state and stream own terminal reporting.
    }
  }

  // TODO: abstract me
  Future<void> _enqueueExclusive(Future<void> Function() action) {
    final previous = _exclusiveWork;
    final result = () async {
      try {
        await previous;
      } catch (_) {
        // A terminal failure is stored separately and must not poison cleanup.
      }
      final failure = _lifecycle.failure;
      if (failure != null) {
        Error.throwWithStackTrace(failure, failure.stackTrace);
      }
      await action();
    }();
    _exclusiveWork = result;
    return result;
  }

  Future<void> _pumpEventPump(EventPump eventPump) async {
    try {
      await eventPump.pump();
    } catch (error, stackTrace) {
      final failure = _lifecycle.recordPumpFailure(error, stackTrace);
      Error.throwWithStackTrace(failure, failure.stackTrace);
    }
  }

  Future<void> close() {
    _lifecycle.beginClosing();
    return _teardown();
  }

  Future<void> _teardown() async {
    await _settle(_scheduledPump);
    await _settle(_exclusiveWork);
    await _settle(_appliedChangesSubscription?.cancel());
    await _settle(_exclusiveWork);
    try {
      await eventStore.close();
    } finally {
      await _lifecycle.completeClosing();
    }
  }

  Future<void> _settle(Future<void>? future) async {
    if (future == null) return;
    try {
      await future;
    } catch (_) {
      // Closing waits for work to settle regardless of its result.
    }
  }
}
