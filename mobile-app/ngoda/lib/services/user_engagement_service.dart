import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:in_app_review/in_app_review.dart';
import 'package:logging/logging.dart';
import 'package:ngoda/services/hive_service.dart';
import 'package:ngoda/services/notification_service.dart';

class UserEngagementService {
  UserEngagementService({required this._hive, required this._notifications});

  final HiveService _hive;
  final NotificationService _notifications;
  final _log = Logger('UserEngagementService');
  final _review = InAppReview.instance;
  final Set<String> _countedUsers = {};
  Future<void> _pending = Future<void>.value();
  String? _userId;
  bool _foreground = true;

  static const reminderDelay = Duration(days: 3);
  static const reviewCooldown = Duration(days: 90);
  static const minimumSessions = 10;
  // Set the numeric Apple App Store ID when an iOS listing exists.
  static const String appStoreId = String.fromEnvironment('NGODA_APP_STORE_ID');

  // Serialize storage and notification changes, including logout/resume races.
  Future<void> _run(Future<void> Function() action) {
    final result = _pending.then((_) => action());
    _pending = result.catchError((Object error, StackTrace stack) {
      _log.warning('Engagement operation failed.', error, stack);
    });
    return _pending;
  }

  Map<String, dynamic> _read(String id) {
    final result = _hive.getItem<String>(HiveBoxName.userEngagement, id);
    if (result.error != null) {
      throw StateError('Unable to read engagement settings.');
    }
    final raw = result.result;
    if (raw == null) {
      return <String, dynamic>{};
    }
    // Preserve unreadable state: do not overwrite it with fresh defaults.
    return Map<String, dynamic>.from(jsonDecode(raw) as Map);
  }

  Future<void> _save(String id, Map<String, dynamic> state) async {
    final result = await _hive.saveItem<String>(
      HiveBoxName.userEngagement,
      id,
      jsonEncode(state),
    );
    if (result.result != true) {
      throw StateError('Unable to save engagement settings.');
    }
  }

  Future<void> startSession(String userId) {
    _userId = userId;
    return _run(() async {
      if (_userId != userId) {
        return;
      }
      await _hive.init();
      await _notifications.cancelEngagementReminder();
      final state = _read(userId);
      if (_countedUsers.add(userId)) {
        state['sessions'] = ((state['sessions'] as num?)?.toInt() ?? 0) + 1;
      }
      state['lastActivity'] = DateTime.now().toUtc().toIso8601String();
      await _save(userId, state);
      if (!_foreground && _userId == userId) {
        await _schedule(userId, state);
      }
    });
  }

  Future<void> setForeground(bool foreground) {
    _foreground = foreground;
    final id = _userId;
    return _run(() async {
      if (id == null || _userId != id) {
        return;
      }
      if (_foreground != foreground) {
        return;
      }
      final state = _read(id);
      state['lastActivity'] = DateTime.now().toUtc().toIso8601String();
      await _save(id, state);
      if (foreground) {
        await _notifications.cancelEngagementReminder();
      } else {
        await _schedule(id, state);
      }
    });
  }

  Future<void> _schedule(String id, Map<String, dynamic> state) async {
    if (_userId != id || _foreground || state['remindersEnabled'] == false) {
      return;
    }
    const messages = [
      'Your Ngoda wallet is a tap away. Open the app to catch up.',
      'Take a moment to check in with Ngoda.',
      'Stay connected with Ngoda. Open the app when it suits you.',
    ];
    final index =
        ((state['messageIndex'] as num?)?.toInt() ?? 0) % messages.length;
    final scheduled = await _notifications.scheduleEngagementReminder(
      when: DateTime.now().add(reminderDelay),
      body: messages[index],
    );
    if (scheduled) {
      state['messageIndex'] = (index + 1) % messages.length;
      await _save(id, state);
    }
  }

  Future<bool> remindersEnabled() async {
    await _pending;
    final id = _userId;
    return id != null && _read(id)['remindersEnabled'] != false;
  }

  Future<void> setRemindersEnabled(bool enabled) {
    final id = _userId;
    return _run(() async {
      if (id == null || id != _userId) {
        return;
      }
      final state = _read(id)..['remindersEnabled'] = enabled;
      await _save(id, state);
      await _notifications.cancelEngagementReminder();
      if (enabled && !_foreground) {
        await _schedule(id, state);
      }
    });
  }

  // Call only at a quiet, unlocked screen, e.g. after dismissing a completed
  // transaction receipt. Do not call in the middle of signing or payment.
  // shouldPrompt is evaluated again after asynchronous availability checks.
  Future<void> maybeRequestReview({required bool Function() shouldPrompt}) {
    final id = _userId;
    return _run(() async {
      if (kDebugMode ||
          id == null ||
          id != _userId ||
          !_foreground ||
          !shouldPrompt()) {
        return;
      }
      final state = _read(id);
      if (((state['sessions'] as num?)?.toInt() ?? 0) < minimumSessions) {
        return;
      }
      final last = DateTime.tryParse(
        state['lastReviewRequest'] as String? ?? '',
      );
      if (last != null &&
          DateTime.now().toUtc().difference(last) < reviewCooldown) {
        return;
      }
      if (!await _review.isAvailable()) {
        return;
      }
      if (_userId != id || !_foreground || !shouldPrompt()) {
        return;
      }
      // Record the attempt before calling the OS. The API cannot tell us
      // whether a dialog appeared or whether the person submitted a review.
      state['lastReviewRequest'] = DateTime.now().toUtc().toIso8601String();
      await _save(id, state);
      await _review.requestReview();
    });
  }

  // Explicit "Rate Ngoda" action; never an automatic fallback redirect.
  Future<void> openStoreListing() async {
    if (defaultTargetPlatform == TargetPlatform.iOS && appStoreId.isEmpty) {
      throw StateError(
        'Configure NGODA_APP_STORE_ID before opening the iOS listing.',
      );
    }
    await _review.openStoreListing(
      appStoreId: appStoreId.isEmpty ? null : appStoreId,
    );
  }

  Future<void> stopSession() {
    _userId = null;
    return _run(() => _notifications.cancelEngagementReminder());
  }
}
