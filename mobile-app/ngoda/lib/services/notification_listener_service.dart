import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:logging/logging.dart';
import 'package:ngoda/services/notification_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class NotificationListenerService {
  NotificationListenerService({
    required this._supabase,
    required this._notificationService,
    this._onWalletChanged,
  });

  final SupabaseClient _supabase;
  final NotificationService _notificationService;
  final VoidCallback? _onWalletChanged;

  final Logger _log = Logger('NotificationListenerService');

  RealtimeChannel? _channel;

  bool _started = false;

  bool get isStarted => _started;

  Future<void> start() async {
    if (_started) {
      _log.fine('Notification listener is already started.');

      return;
    }

    final currentUser = _supabase.auth.currentUser;

    if (currentUser == null) {
      _log.warning(
        'Notification listener cannot start '
        'without an authenticated user.',
      );

      return;
    }

    /*
     * Remove any stale channel left behind by a
     * previous unsuccessful start/restart.
     */
    await _removeCurrentChannel();

    final channel = _supabase.channel('notifications:${currentUser.id}');

    _channel = channel;

    channel
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'notifications',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'user_id',
            value: currentUser.id,
          ),
          callback: (payload) {
            /*
             * Stream callbacks are not awaited by
             * Supabase Realtime, so make the
             * asynchronous behavior explicit.
             */
            unawaited(_handleNotification(channel, payload));
          },
        )
        .subscribe((status, [error]) {
          _handleSubscriptionStatus(channel, status, error);
        });

    _started = true;

    _log.info('Notification listener started.');
  }

  Future<void> _handleNotification(
    RealtimeChannel sourceChannel,
    PostgresChangePayload payload,
  ) async {
    /*
     * Ignore late events from a channel that was
     * stopped or replaced while the callback was
     * waiting to execute.
     */
    if (!_started || !identical(_channel, sourceChannel)) {
      return;
    }

    try {
      final notification = payload.newRecord;

      final id = notification['id'];

      final title = notification['title']?.toString().trim();

      final body = notification['body']?.toString().trim();

      if (id == null) {
        _log.warning('Ignoring notification without an ID.');

        return;
      }

      if (title == null || title.isEmpty || body == null || body.isEmpty) {
        _log.warning(
          'Ignoring notification $id because '
          'title or body is missing.',
        );

        return;
      }

      await _notificationService.showLocalNotification(
        id: id,
        title: title,
        body: body,
      );

      await _notificationService.markAsDelivered(id);

      /*
       * Preserve the existing application
       * behavior for now.
       *
       * We will review whether wallet refresh
       * should depend on notification type when
       * NotificationService and notification
       * models are reviewed.
       */
      _onWalletChanged?.call();
    } catch (error, stackTrace) {
      _log.severe(
        'Failed to process realtime notification.',
        error,
        stackTrace,
      );
    }
  }

  void _handleSubscriptionStatus(
    RealtimeChannel sourceChannel,
    RealtimeSubscribeStatus status,
    Object? error,
  ) {
    if (!identical(_channel, sourceChannel)) {
      return;
    }

    if (error != null) {
      _log.warning('Notification realtime subscription error.', error);

      return;
    }

    _log.fine('Notification realtime status: $status');
  }

  Future<void> stop() async {
    if (!_started && _channel == null) {
      return;
    }

    _started = false;

    await _removeCurrentChannel();

    _log.info('Notification listener stopped.');
  }

  Future<void> _removeCurrentChannel() async {
    final channel = _channel;

    _channel = null;

    if (channel == null) {
      return;
    }

    try {
      await _supabase.removeChannel(channel);
    } catch (error, stackTrace) {
      _log.warning(
        'Failed to remove notification '
        'realtime channel.',
        error,
        stackTrace,
      );
    }
  }

  Future<void> dispose() async {
    await stop();
  }
}
