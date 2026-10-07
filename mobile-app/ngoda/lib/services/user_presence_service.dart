import 'package:logging/logging.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

abstract final class UserPresenceService {
  static final Logger _log = Logger('UserPresenceService');

  static RealtimeChannel? _channel;

  static String? _trackedUserId;

  static bool get isStarted => _channel != null;

  static String? get trackedUserId => _trackedUserId;

  static Future<void> start() async {
    final supabase = Supabase.instance.client;

    final user = supabase.auth.currentUser;

    if (user == null) {
      _log.fine(
        'Presence not started because '
        'there is no authenticated user.',
      );

      return;
    }

    /*
     * Remove any previous presence session before
     * establishing a new one.
     *
     * This also handles account/session changes
     * cleanly.
     */
    await stop();

    final userId = user.id;

    final channel = supabase.channel(
      'online-users',
      opts: RealtimeChannelConfig(key: userId, enabled: true),
    );

    _channel = channel;
    _trackedUserId = userId;

    channel
        .onPresenceSync((_) {
          if (!_isCurrentChannel(channel)) {
            return;
          }

          _log.fine('Presence synchronized.');
        })
        .onPresenceJoin((_) {
          if (!_isCurrentChannel(channel)) {
            return;
          }

          _log.fine('Presence member joined.');
        })
        .onPresenceLeave((_) {
          if (!_isCurrentChannel(channel)) {
            return;
          }

          _log.fine('Presence member left.');
        })
        .subscribe((status, [error]) {
          _handleSubscriptionStatus(
            supabase: supabase,
            channel: channel,
            userId: userId,
            status: status,
            error: error,
          );
        });
  }

  static void _handleSubscriptionStatus({
    required SupabaseClient supabase,
    required RealtimeChannel channel,
    required String userId,
    required RealtimeSubscribeStatus status,
    required Object? error,
  }) {
    if (!_isCurrentChannel(channel)) {
      return;
    }

    if (error != null) {
      _log.warning('Presence subscription reported an error.', error);
    }

    switch (status) {
      case RealtimeSubscribeStatus.subscribed:
        _log.fine('Presence channel subscribed.');

        _markOnline(supabase: supabase, channel: channel, userId: userId);

      case RealtimeSubscribeStatus.channelError:
        _log.warning('Presence channel encountered an error.');

      case RealtimeSubscribeStatus.timedOut:
        _log.warning('Presence channel subscription timed out.');

      case RealtimeSubscribeStatus.closed:
        _log.fine('Presence channel closed.');
    }
  }

  static Future<void> _markOnline({
    required SupabaseClient supabase,
    required RealtimeChannel channel,
    required String userId,
  }) async {
    if (!_isCurrentChannel(channel)) {
      return;
    }

    final now = DateTime.now().toUtc().toIso8601String();

    try {
      await channel.track({'user_id': userId, 'online_at': now});

      if (!_isCurrentChannel(channel)) {
        return;
      }

      await supabase.from('user_presence').upsert({
        'user_id': userId,
        'is_online': true,
        'last_seen_at': now,
      });

      _log.fine('User presence marked online.');
    } catch (error, stackTrace) {
      _log.warning('Unable to mark user presence online.', error, stackTrace);
    }
  }

  static Future<void> stop() async {
    final channel = _channel;

    final userId = _trackedUserId;

    if (channel == null) {
      _trackedUserId = null;
      return;
    }

    /*
     * Clear the active references first so late
     * subscription callbacks cannot mark the user
     * online again while shutdown is in progress.
     */
    _channel = null;
    _trackedUserId = null;

    final supabase = Supabase.instance.client;

    if (userId != null) {
      await _markOffline(supabase: supabase, userId: userId);
    }

    try {
      await channel.untrack();

      _log.fine('Presence untracked.');
    } catch (error, stackTrace) {
      _log.warning('Unable to untrack presence.', error, stackTrace);
    }

    try {
      await supabase.removeChannel(channel);

      _log.fine('Presence channel removed.');
    } catch (error, stackTrace) {
      _log.warning('Unable to remove presence channel.', error, stackTrace);
    }
  }

  static Future<void> _markOffline({
    required SupabaseClient supabase,
    required String userId,
  }) async {
    try {
      await supabase
          .from('user_presence')
          .update({
            'is_online': false,
            'last_seen_at': DateTime.now().toUtc().toIso8601String(),
          })
          .eq('user_id', userId);

      _log.fine('User presence marked offline.');
    } catch (error, stackTrace) {
      _log.warning('Unable to mark user presence offline.', error, stackTrace);
    }
  }

  static bool _isCurrentChannel(RealtimeChannel channel) {
    return identical(_channel, channel);
  }
}
