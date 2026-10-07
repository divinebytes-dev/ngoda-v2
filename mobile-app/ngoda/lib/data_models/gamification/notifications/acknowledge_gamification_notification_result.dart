class AcknowledgeGamificationNotificationResult {
  const AcknowledgeGamificationNotificationResult({
    required this.success,
    required this.notificationId,
    required this.displayedAt,
    required this.seenAt,
  });

  final bool success;

  final String notificationId;

  final DateTime displayedAt;
  final DateTime? seenAt;

  factory AcknowledgeGamificationNotificationResult.fromJson(
    Map<String, dynamic> json,
  ) {
    return AcknowledgeGamificationNotificationResult(
      success: json['success'] == true,
      notificationId: _requiredString(
        json['notification_id'],
        'notification_id',
      ),
      displayedAt: _requiredDateTime(json['displayed_at'], 'displayed_at'),
      seenAt: _nullableDateTime(json['seen_at']),
    );
  }

  static String _requiredString(dynamic value, String field) {
    final result = value?.toString().trim();

    if (result == null || result.isEmpty) {
      throw FormatException(
        'AcknowledgeGamificationNotificationResult.'
        '$field is required.',
      );
    }

    return result;
  }

  static DateTime _requiredDateTime(dynamic value, String field) {
    final raw = value?.toString().trim();

    if (raw == null || raw.isEmpty) {
      throw FormatException(
        'AcknowledgeGamificationNotificationResult.'
        '$field is required.',
      );
    }

    final parsed = DateTime.tryParse(raw);

    if (parsed == null) {
      throw FormatException(
        'AcknowledgeGamificationNotificationResult.'
        '$field is invalid.',
      );
    }

    return parsed.toLocal();
  }

  static DateTime? _nullableDateTime(dynamic value) {
    final raw = value?.toString().trim();

    if (raw == null || raw.isEmpty) {
      return null;
    }

    return DateTime.tryParse(raw)?.toLocal();
  }
}
