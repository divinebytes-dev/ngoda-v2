import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ngoda/core/providers/idle_service_provider.dart';
import 'package:ngoda/services/nfc_router_service.dart';
import 'package:ngoda/services/user_presence_service.dart';
import 'package:ngoda/ui/screens/auth/providers/auth_provider.dart';

final appLifecycleServiceProvider =
    Provider.family<AppLifecycleService, GlobalKey<NavigatorState>>((
      ref,
      navigatorKey,
    ) {
      final service = AppLifecycleService(ref: ref, navigatorKey: navigatorKey);

      service.start();

      ref.onDispose(service.dispose);

      return service;
    });

class AppLifecycleService with WidgetsBindingObserver {
  final Ref ref;

  final GlobalKey<NavigatorState> navigatorKey;

  AppLifecycleState? _lastState;

  DateTime? _lastPausedAt;

  bool _backgroundLockApplied = false;

  bool _started = false;

  AppLifecycleService({required this.ref, required this.navigatorKey});

  bool get _hasActiveSession {
    if (!ref.mounted) {
      return false;
    }

    final auth = ref.read(authProvider);

    return auth.isAuthenticated;
  }

  void start() {
    if (_started) {
      return;
    }

    _started = true;

    WidgetsBinding.instance.addObserver(this);
  }

  void dispose() {
    if (!_started) {
      return;
    }

    _started = false;

    WidgetsBinding.instance.removeObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!ref.mounted) {
      return;
    }

    _lastState = state;

    switch (state) {
      case AppLifecycleState.resumed:
        _onResumed();
        break;

      case AppLifecycleState.inactive:
        _onInactive();
        break;

      case AppLifecycleState.paused:
        _onPaused();
        break;

      case AppLifecycleState.hidden:
        _onHidden();
        break;

      case AppLifecycleState.detached:
        _onDetached();
        break;
    }
  }

  void _onResumed() {
    if (!ref.mounted) {
      return;
    }

    _lastPausedAt = null;

    _backgroundLockApplied = false;

    if (!_hasActiveSession) {
      UserPresenceService.stop();

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!ref.mounted) {
          return;
        }

        final context = navigatorKey.currentContext;

        if (context == null) {
          return;
        }

        NFCRouterService.restart(
          ProviderScope.containerOf(context),
          navigatorKey,
        );
      });

      return;
    }

    ref.read(idleServiceProvider).checkInactivity();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!ref.mounted) {
        return;
      }

      final context = navigatorKey.currentContext;

      if (context == null) {
        return;
      }

      if (!_hasActiveSession) {
        UserPresenceService.stop();

        return;
      }

      NFCRouterService.restart(
        ProviderScope.containerOf(context),
        navigatorKey,
      );

      UserPresenceService.start();
    });
  }

  void _onInactive() {
    // Deliberately ignored.
    //
    // Flutter may report inactive for:
    // - biometrics
    // - permission dialogs
    // - system overlays
    // - incoming calls
    //
    // Locking here can cause repeated
    // lock/biometric lifecycle loops.
  }

  void _onPaused() {
    _lastPausedAt ??= DateTime.now();

    _lockForBackground();
  }

  void _onHidden() {
    _lastPausedAt ??= DateTime.now();

    _lockForBackground();
  }

  void _onDetached() {
    _lastPausedAt ??= DateTime.now();

    UserPresenceService.stop();
  }

  void _lockForBackground() {
    if (!ref.mounted) {
      return;
    }

    if (!_hasActiveSession) {
      _backgroundLockApplied = false;

      UserPresenceService.stop();

      return;
    }

    if (_backgroundLockApplied) {
      return;
    }

    _backgroundLockApplied = true;

    final auth = ref.read(authProvider);

    if (!auth.isLocked) {
      ref.read(authProvider.notifier).lock();
    }

    UserPresenceService.stop();
  }

  AppLifecycleState? get lastState => _lastState;

  DateTime? get lastPausedAt => _lastPausedAt;

  Duration? get timeInBackground {
    final pausedAt = _lastPausedAt;

    if (pausedAt == null) {
      return null;
    }

    return DateTime.now().difference(pausedAt);
  }
}
