import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';

import 'package:ngoda/ui/screens/auth/providers/auth_provider.dart';

final idleServiceProvider = Provider<IdleService>((ref) {
  final service = IdleService(ref);

  ref.onDispose(service.dispose);

  return service;
});

class IdleService {
  final Ref ref;

  Timer? _idleTimer;

  DateTime? _lastActivity;

  static const idleDuration = Duration(minutes: 10);

  static const warningDuration = Duration(seconds: 30);

  final logger = Logger('IdleService');

  IdleService(this.ref);

  void start() {
    if (!_isActiveSession()) {
      logger.info(
        'Idle service not started - '
        'user not authenticated',
      );

      stop();

      return;
    }

    logger.info('Idle service starts');

    _idleTimer?.cancel();

    _markActivity();

    _startIdleTimer();
  }

  void stop() {
    logger.info('Idle service stops');

    _idleTimer?.cancel();

    _idleTimer = null;

    _lastActivity = null;
  }

  void dispose() {
    _idleTimer?.cancel();

    _idleTimer = null;

    _lastActivity = null;
  }

  void userActivity() {
    if (!_isActiveSession()) {
      stop();

      return;
    }

    _markActivity();

    _startIdleTimer();
  }

  void _markActivity() {
    _lastActivity = DateTime.now();
  }

  bool _isActiveSession() {
    if (!ref.mounted) {
      return false;
    }

    final auth = ref.read(authProvider);

    return auth.isAuthenticated;
  }

  void _startIdleTimer() {
    _idleTimer?.cancel();

    _idleTimer = null;

    if (!_isActiveSession()) {
      _lastActivity = null;

      return;
    }

    _idleTimer = Timer(idleDuration, _onIdleReached);
  }

  void _onIdleReached() {
    if (!_isActiveSession()) {
      stop();

      return;
    }

    _lockUser();
  }

  void lockNow() {
    if (!_isActiveSession()) {
      return;
    }

    _lockUser();
  }

  void _lockUser() {
    if (!ref.mounted) {
      return;
    }

    if (!_isActiveSession()) {
      stop();

      return;
    }

    logger.info('Idle service lock screen');

    _idleTimer?.cancel();

    _idleTimer = null;

    ref.read(authProvider.notifier).lock();
  }

  void checkInactivity() {
    if (!_isActiveSession()) {
      stop();

      return;
    }

    final lastActivity = _lastActivity;

    if (lastActivity == null) {
      _markActivity();

      _startIdleTimer();

      return;
    }

    final elapsed = DateTime.now().difference(lastActivity);

    if (elapsed >= idleDuration) {
      _lockUser();

      return;
    }

    final remaining = idleDuration - elapsed;

    _idleTimer?.cancel();

    _idleTimer = Timer(remaining, _onIdleReached);
  }
}
