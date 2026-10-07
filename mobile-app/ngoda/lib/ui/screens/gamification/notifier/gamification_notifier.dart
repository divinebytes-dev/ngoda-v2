import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ngoda/data_models/gamification/notifications/gamification_notification.dart';
import 'package:ngoda/ui/screens/gamification/services/gamification_api_service.dart';
import 'package:ngoda/ui/screens/gamification/services/gamification_api_service_provider.dart';
import 'package:ngoda/ui/screens/gamification/state/gamification_state.dart';

class GamificationNotifier extends Notifier<GamificationState> {
  late final GamificationApiService _api;

  final Set<String> _knownNotificationIds = <String>{};

  Future<void>? _activeAcknowledgement;

  @override
  GamificationState build() {
    _api = ref.read(gamificationApiServiceProvider);

    ref.onDispose(() {
      _knownNotificationIds.clear();
      _activeAcknowledgement = null;
    });

    return const GamificationState();
  }

  Future<void> start() async {
    if (state.isStarted) {
      return;
    }

    state = state.copyWith(isStarted: true, error: null);

    await refresh();
  }

  void stop() {
    _knownNotificationIds.clear();
    _activeAcknowledgement = null;

    state = const GamificationState();
  }

  Future<void> refresh() async {
    if (!state.isStarted || state.isLoading) {
      return;
    }

    state = state.copyWith(isLoading: true, error: null);

    try {
      final feed = await _api.fetchGamificationNotifications();

      final pending = List<GamificationNotification>.from(
        state.pendingNotifications,
      );

      for (final notification in feed.rows) {
        if (_knownNotificationIds.add(notification.id)) {
          pending.add(notification);
        }
      }

      pending.sort((left, right) {
        final priority = left.displayPriority.compareTo(right.displayPriority);

        if (priority != 0) {
          return priority;
        }

        return left.createdAt.compareTo(right.createdAt);
      });

      state = state.copyWith(isLoading: false, pendingNotifications: pending);

      _selectNext();
    } catch (error) {
      state = state.copyWith(isLoading: false, error: error.toString());
    }
  }

  Future<void> acknowledgeCurrent() {
    final notification = state.currentNotification;

    if (notification == null) {
      return Future<void>.value();
    }

    final activeAcknowledgement = _activeAcknowledgement;

    if (activeAcknowledgement != null) {
      return activeAcknowledgement;
    }

    final acknowledgement = _acknowledge(notification);

    _activeAcknowledgement = acknowledgement;

    return acknowledgement;
  }

  Future<void> _acknowledge(GamificationNotification notification) async {
    try {
      await _api.acknowledgeGamificationNotification(
        notificationId: notification.id,
        markSeen: false,
      );
    } catch (error) {
      _knownNotificationIds.remove(notification.id);

      state = state.copyWith(error: error.toString());

      rethrow;
    }
  }

  Future<void> completeCurrent() async {
    final acknowledgement = _activeAcknowledgement;

    if (acknowledgement != null) {
      try {
        await acknowledgement;
      } catch (_) {
        /*
         * The acknowledgement error is already stored
         * in state.
         *
         * Removing the notification ID from the known
         * set allows it to be fetched again later.
         */
      }
    }

    _activeAcknowledgement = null;

    state = state.copyWith(currentNotification: null);

    _selectNext();
  }

  void _selectNext() {
    if (!state.isStarted || state.currentNotification != null) {
      return;
    }

    final pending = List<GamificationNotification>.from(
      state.pendingNotifications,
    );

    if (pending.isEmpty) {
      return;
    }

    final next = pending.removeAt(0);

    state = state.copyWith(
      pendingNotifications: pending,
      currentNotification: next,
    );
  }
}
