import 'dart:math' as math;

abstract class RetryStrategy {
  Duration getTimeout(int attemptIndex);
}

class RetryStrategyConstantBackoff extends RetryStrategy {
  final Duration duration;

  RetryStrategyConstantBackoff({required this.duration});

  @override
  Duration getTimeout(int attemptIndex) {
    return duration;
  }
}

class RetryStrategyExponentialBackoff implements RetryStrategy {
  final Duration _maxDuration;

  RetryStrategyExponentialBackoff(this._maxDuration);

  @override
  Duration getTimeout(int attemptIndex) {
    if (attemptIndex == 0) {
      return Duration.zero;
    }

    final millis =
        math
            .min(1000 * math.pow(2, attemptIndex), _maxDuration.inMilliseconds)
            .toInt();

    return Duration(milliseconds: millis);
  }
}

@Deprecated('bad idea to use this?')
class ManagedRetry<T> {
  final RetryStrategy strategy;
  final int maxRetries;
  final Future<T> Function() fn;

  const ManagedRetry(this.strategy, this.fn, {required this.maxRetries});

  Future<T> attempt({Function(Object)? onSoftFail}) async {
    int attemptIndex = 0;

    while (true) {
      try {
        final timeout = strategy.getTimeout(attemptIndex);
        await Future.delayed(timeout);

        return await fn();
      } catch (e) {
        if (onSoftFail != null) {
          onSoftFail(e);
        }
        attemptIndex++;
        if (attemptIndex > maxRetries) {
          rethrow;
        }
      }
    }
  }
}
