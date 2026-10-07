import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:logging/logging.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class TransactionStatusListenerService {
  TransactionStatusListenerService({required this._supabase});

  final SupabaseClient _supabase;

  final Logger _log = Logger('TransactionStatusListenerService');

  RealtimeChannel? _channel;

  String? _activeReference;

  bool _successTriggered = false;

  bool get isListening => _channel != null;

  String? get activeReference => _activeReference;

  Future<void> listenForTransactionStatus({
    required String reference,
    required VoidCallback onTransactionSuccess,
    required ValueChanged<String> onStatusChange,
  }) async {
    final normalizedReference = reference.trim();

    if (normalizedReference.isEmpty) {
      throw ArgumentError.value(
        reference,
        'reference',
        'Transaction reference cannot be empty.',
      );
    }

    final currentUser = _supabase.auth.currentUser;

    if (currentUser == null) {
      _log.warning(
        'Cannot listen for transaction status '
        'without an authenticated user.',
      );

      return;
    }

    /*
     * A service instance owns one active transaction
     * listener at a time.
     */
    await stop();

    _activeReference = normalizedReference;

    _successTriggered = false;

    final channel = _supabase.channel(
      'transaction-status:'
      '${currentUser.id}:'
      '$normalizedReference',
    );

    _channel = channel;

    channel
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'transaction_state',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'reference',
            value: normalizedReference,
          ),
          callback: (payload) {
            unawaited(
              _handleRecord(
                channel: channel,
                reference: normalizedReference,
                expectedUserId: currentUser.id,
                record: payload.newRecord,
                onTransactionSuccess: onTransactionSuccess,
                onStatusChange: onStatusChange,
              ),
            );
          },
        )
        .subscribe((status, [error]) {
          _handleSubscriptionStatus(
            channel: channel,
            reference: normalizedReference,
            status: status,
            error: error,
            currentUserId: currentUser.id,
            onTransactionSuccess: onTransactionSuccess,
            onStatusChange: onStatusChange,
          );
        });
  }

  void _handleSubscriptionStatus({
    required RealtimeChannel channel,
    required String reference,
    required RealtimeSubscribeStatus status,
    required Object? error,
    required String currentUserId,
    required VoidCallback onTransactionSuccess,
    required ValueChanged<String> onStatusChange,
  }) {
    if (!identical(_channel, channel)) {
      return;
    }

    if (error != null) {
      _log.warning(
        'Transaction realtime subscription '
        'reported an error for $reference.',
        error,
      );
    }

    switch (status) {
      case RealtimeSubscribeStatus.subscribed:
        _log.fine(
          'Subscribed to transaction status '
          'updates for $reference.',
        );

        /*
         * Close the race between creating the
         * transaction and establishing the realtime
         * subscription.
         *
         * The transaction may already have changed
         * status before Realtime became active.
         */
        unawaited(
          _loadCurrentStatus(
            channel: channel,
            reference: reference,
            expectedUserId: currentUserId,
            onTransactionSuccess: onTransactionSuccess,
            onStatusChange: onStatusChange,
          ),
        );

      case RealtimeSubscribeStatus.channelError:
        _log.warning(
          'Transaction status channel failed '
          'for $reference.',
        );

      case RealtimeSubscribeStatus.timedOut:
        _log.warning(
          'Transaction status subscription '
          'timed out for $reference.',
        );

      case RealtimeSubscribeStatus.closed:
        _log.fine(
          'Transaction status channel closed '
          'for $reference.',
        );
    }
  }

  Future<void> _loadCurrentStatus({
    required RealtimeChannel channel,
    required String reference,
    required String expectedUserId,
    required VoidCallback onTransactionSuccess,
    required ValueChanged<String> onStatusChange,
  }) async {
    if (!identical(_channel, channel)) {
      return;
    }

    try {
      final record = await _supabase
          .from('transaction_state')
          .select('reference,user_id,status')
          .eq('reference', reference)
          .eq('user_id', expectedUserId)
          .maybeSingle();

      if (record == null) {
        return;
      }

      await _handleRecord(
        channel: channel,
        reference: reference,
        expectedUserId: expectedUserId,
        record: Map<String, dynamic>.from(record),
        onTransactionSuccess: onTransactionSuccess,
        onStatusChange: onStatusChange,
      );
    } catch (error, stackTrace) {
      _log.warning(
        'Unable to read current transaction '
        'status for $reference.',
        error,
        stackTrace,
      );
    }
  }

  Future<void> _handleRecord({
    required RealtimeChannel channel,
    required String reference,
    required String expectedUserId,
    required Map<String, dynamic> record,
    required VoidCallback onTransactionSuccess,
    required ValueChanged<String> onStatusChange,
  }) async {
    if (!identical(_channel, channel)) {
      return;
    }

    if (_activeReference != reference) {
      return;
    }

    if (_successTriggered || record.isEmpty) {
      return;
    }

    try {
      final userId = record['user_id']?.toString();

      if (userId != expectedUserId) {
        _log.warning(
          'Ignoring transaction status update '
          'for another user.',
        );

        return;
      }

      final status = record['status']?.toString().trim().toLowerCase();

      if (status == null || status.isEmpty) {
        return;
      }

      _log.fine(
        'Transaction $reference '
        'status changed to $status.',
      );

      onStatusChange(status);

      if (status != 'success') {
        return;
      }

      /*
       * Set the guard before invoking the callback.
       * The initial database read and realtime event
       * may both observe the same successful state.
       */
      _successTriggered = true;

      onTransactionSuccess();

      await _stopChannel(channel);
    } catch (error, stackTrace) {
      _log.warning(
        'Failed to process transaction status '
        'for $reference.',
        error,
        stackTrace,
      );
    }
  }

  Future<void> stop() async {
    final channel = _channel;

    _channel = null;
    _activeReference = null;
    _successTriggered = false;

    if (channel == null) {
      return;
    }

    await _removeChannel(channel);
  }

  Future<void> _stopChannel(RealtimeChannel channel) async {
    if (!identical(_channel, channel)) {
      return;
    }

    _channel = null;
    _activeReference = null;

    await _removeChannel(channel);
  }

  Future<void> _removeChannel(RealtimeChannel channel) async {
    try {
      await _supabase.removeChannel(channel);
    } catch (error, stackTrace) {
      _log.warning(
        'Unable to remove transaction '
        'status realtime channel.',
        error,
        stackTrace,
      );
    }
  }

  Future<void> dispose() async {
    await stop();
  }
}
