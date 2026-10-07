import 'dart:ui';

import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';
import 'package:logging/logging.dart';

class CrashlyticsService {
  final Logger _log = Logger('CrashlyticsService');

  final FirebaseCrashlytics _crashlytics = FirebaseCrashlytics.instance;

  Future<void> initialize() async {
    FlutterError.onError = _crashlytics.recordFlutterFatalError;

    PlatformDispatcher.instance.onError =
        (Object error, StackTrace stackTrace) {
          _crashlytics.recordError(error, stackTrace, fatal: true);

          return true;
        };
  }

  Future<void> recordError(
    Object error,
    StackTrace? stackTrace, {
    String? reason,
    bool fatal = false,
  }) async {
    try {
      await _crashlytics.recordError(
        error,
        stackTrace,
        reason: reason,
        fatal: fatal,
      );
    } catch (crashlyticsError, crashlyticsStackTrace) {
      _log.warning(
        'Failed to record Crashlytics error.',
        crashlyticsError,
        crashlyticsStackTrace,
      );
    }
  }

  Future<void> log(String message) async {
    try {
      await _crashlytics.log(message);
    } catch (error, stackTrace) {
      _log.warning('Failed to write Crashlytics log.', error, stackTrace);
    }
  }

  Future<void> setUserId(String? userId) async {
    try {
      /*
       * Firebase Crashlytics expects a string.
       * An empty value clears the current
       * application user association.
       */
      await _crashlytics.setUserIdentifier(userId ?? '');
    } catch (error, stackTrace) {
      _log.warning('Failed to set Crashlytics user ID.', error, stackTrace);
    }
  }

  Future<void> setCustomKey(String key, Object value) async {
    try {
      await _crashlytics.setCustomKey(key, value);
    } catch (error, stackTrace) {
      _log.warning('Failed to set Crashlytics custom key.', error, stackTrace);
    }
  }
}
