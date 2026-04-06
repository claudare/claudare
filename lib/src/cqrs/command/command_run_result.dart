import 'package:core/src/cqrs/exception/command_execution_exception.dart';
import 'package:core/src/cqrs/exception/command_nack.dart';
import 'package:core/src/cqrs/exception/concurrency_problem.dart';

/// Result available to the library user
class CommandRunResult {
  final String? nackReason;
  // this cannot be an error. An error is propagated up, never swallowed
  final Exception? exception;
  final bool isConcurrencyProblem;

  bool get success =>
      nackReason == null && exception == null && !isConcurrencyProblem;

  const CommandRunResult._({
    required this.nackReason,
    required this.exception,
    required this.isConcurrencyProblem,
  });

  const CommandRunResult._success()
    : this._(nackReason: null, exception: null, isConcurrencyProblem: false);

  const CommandRunResult._nack({required String reason})
    : this._(nackReason: reason, exception: null, isConcurrencyProblem: false);

  const CommandRunResult._exception({required Exception exception})
    : this._(
        nackReason: null,
        exception: exception,
        isConcurrencyProblem: false,
      );

  const CommandRunResult._concurrencyProblem()
    : this._(nackReason: null, exception: null, isConcurrencyProblem: true);
}

/// Wraps command execution from a [Future]. Errors are available in the result.
/// Note: Only exceptions are handled. [Error] are not captured and propagated.
Future<CommandRunResult> wrapCommandExecutionFuture(Future<void> future) async {
  try {
    await future;
    return CommandRunResult._success();
  } on CommandNack catch (e) {
    return CommandRunResult._nack(reason: e.message);
  } on ConcurrencyProblem catch (_) {
    return CommandRunResult._concurrencyProblem();
  } on CommandExecutionException catch (e) {
    return CommandRunResult._exception(exception: e.cause);
  } on Exception catch (e) {
    return CommandRunResult._exception(exception: e);
  } catch (e, stackTrace) {
    Error.throwWithStackTrace(e, stackTrace);
  }
}
