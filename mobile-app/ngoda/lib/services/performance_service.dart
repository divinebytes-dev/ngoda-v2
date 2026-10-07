import 'package:firebase_performance/firebase_performance.dart';
import 'package:logging/logging.dart';

class PerformanceService {
  PerformanceService({FirebasePerformance? performance})
    : _performance = performance ?? FirebasePerformance.instance;

  final FirebasePerformance _performance;

  final Logger _log = Logger('PerformanceService');

  Future<T> trace<T>(String name, Future<T> Function() action) async {
    final trace = _performance.newTrace(name);

    var started = false;

    try {
      try {
        await trace.start();
        started = true;
      } catch (error, stackTrace) {
        _log.warning(
          'Failed to start performance trace: $name',
          error,
          stackTrace,
        );
      }

      return await action();
    } finally {
      if (started) {
        await _stopTraceSafely(trace, name: name);
      }
    }
  }

  Future<Trace> startTrace(String name) async {
    final trace = _performance.newTrace(name);

    try {
      await trace.start();
    } catch (error, stackTrace) {
      _log.warning(
        'Failed to start performance trace: $name',
        error,
        stackTrace,
      );
    }

    return trace;
  }

  Future<void> stopTrace(Trace trace) async {
    await _stopTraceSafely(trace);
  }

  void putAttribute(Trace trace, {required String key, required String value}) {
    try {
      trace.putAttribute(key, value);
    } catch (error, stackTrace) {
      _log.warning(
        'Failed to add performance '
        'trace attribute: $key',
        error,
        stackTrace,
      );
    }
  }

  void incrementMetric(Trace trace, {required String metric, int value = 1}) {
    try {
      trace.incrementMetric(metric, value);
    } catch (error, stackTrace) {
      _log.warning(
        'Failed to increment performance '
        'metric: $metric',
        error,
        stackTrace,
      );
    }
  }

  Future<void> _stopTraceSafely(Trace trace, {String? name}) async {
    try {
      await trace.stop();
    } catch (error, stackTrace) {
      _log.warning(
        name == null
            ? 'Failed to stop performance trace.'
            : 'Failed to stop performance trace: $name',
        error,
        stackTrace,
      );
    }
  }
}
