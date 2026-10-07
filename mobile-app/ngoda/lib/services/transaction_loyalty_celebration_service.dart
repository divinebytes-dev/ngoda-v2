import 'dart:async';

import 'package:flutter/material.dart';

import 'package:ngoda/data_models/gamification/loyalty/transaction_loyalty_result.dart';
import 'package:ngoda/data_models/gamification/notifications/gamification_notification.dart';
import 'package:ngoda/ui/widgets/gamification_celebration_overlay.dart';

abstract final class TransactionLoyaltyCelebrationService {
  static Future<void> show(
    BuildContext context,
    TransactionLoyaltyResult? result,
  ) async {
    if (!context.mounted || result == null || !result.shouldCelebrate) {
      return;
    }

    final overlay = Overlay.maybeOf(context, rootOverlay: true);

    if (overlay == null) {
      return;
    }

    final notification = result.levelChanged
        ? _levelNotification(result)
        : _pointsNotification(result);

    final completed = Completer<void>();

    late final OverlayEntry entry;

    entry = OverlayEntry(
      builder: (overlayContext) {
        return GamificationCelebrationOverlay(
          notification: notification,
          duration: const Duration(seconds: 2),
          onPresented: () {},
          onComplete: () {
            if (entry.mounted) {
              entry.remove();
            }

            if (!completed.isCompleted) {
              completed.complete();
            }
          },
        );
      },
    );

    overlay.insert(entry);

    await completed.future;
  }

  static GamificationNotification _pointsNotification(
    TransactionLoyaltyResult result,
  ) {
    return GamificationNotification(
      id: _localId('points'),
      eventId: null,
      notificationType: 'points_earned',
      points: result.pointsEarned,
      title: 'Points earned!',
      subtitle: 'New balance: ${result.availablePoints} points',
      displayPriority: 0,
      payload: {
        'points_earned': result.pointsEarned,
        'available_points': result.availablePoints,
        'tier_points': result.tierPoints,
      },
      seenAt: null,
      displayedAt: null,
      createdAt: DateTime.now(),
    );
  }

  static GamificationNotification _levelNotification(
    TransactionLoyaltyResult result,
  ) {
    final levelName = _formatLevelName(result.levelCode);

    final subtitleParts = <String>[
      if (result.pointsEarned > 0) '+${result.pointsEarned} points',
      'New balance: ${result.availablePoints} points',
    ];

    return GamificationNotification(
      id: _localId('level'),
      eventId: null,
      notificationType: 'level_up',
      points: result.pointsEarned,
      title: '$levelName unlocked!',
      subtitle: subtitleParts.join(' • '),
      displayPriority: 0,
      payload: {
        'points_earned': result.pointsEarned,
        'available_points': result.availablePoints,
        'tier_points': result.tierPoints,
        'previous_level_code': result.previousLevelCode,
        'level_code': result.levelCode,
      },
      seenAt: null,
      displayedAt: null,
      createdAt: DateTime.now(),
    );
  }

  static String _localId(String type) {
    return 'transaction-$type-'
        '${DateTime.now().microsecondsSinceEpoch}';
  }

  static String _formatLevelName(String? value) {
    final normalized = value?.trim() ?? '';

    if (normalized.isEmpty) {
      return 'New level';
    }

    return normalized
        .split(RegExp(r'[_\s-]+'))
        .where((part) => part.isNotEmpty)
        .map(
          (part) =>
              '${part[0].toUpperCase()}'
              '${part.substring(1).toLowerCase()}',
        )
        .join(' ');
  }
}
