import 'package:ngoda/data_models/gamification/notifications/gamification_notification.dart';
import 'package:ngoda/services/number_conversion_service.dart';

class GamificationNotificationFeed {
  GamificationNotificationFeed({
    required List<GamificationNotification> rows,
    required this.count,
  }) : rows = List.unmodifiable(rows);

  final List<GamificationNotification> rows;

  final int count;

  factory GamificationNotificationFeed.fromJson(Map<String, dynamic> json) {
    final rows = _parseRows(json['rows']);

    return GamificationNotificationFeed(
      rows: rows,
      count: json['count'] == null
          ? rows.length
          : NumberConversionService.toInt(json['count']),
    );
  }

  bool get isEmpty => rows.isEmpty;

  bool get isNotEmpty => rows.isNotEmpty;

  bool get hasPendingNotifications =>
      rows.any((notification) => notification.isPendingDisplay);

  List<GamificationNotification> get pendingNotifications {
    return List.unmodifiable(
      rows.where((notification) => notification.isPendingDisplay),
    );
  }

  List<GamificationNotification> forType(String notificationType) {
    final normalized = notificationType.trim().toLowerCase();

    return List.unmodifiable(
      rows.where((notification) => notification.notificationType == normalized),
    );
  }

  static List<GamificationNotification> _parseRows(dynamic value) {
    if (value is! List) {
      return const [];
    }

    return value
        .whereType<Map>()
        .map(
          (row) =>
              GamificationNotification.fromJson(Map<String, dynamic>.from(row)),
        )
        .toList();
  }
}
