import 'package:ngoda/services/number_conversion_service.dart';

class GamificationNotification {
  GamificationNotification({
    required this.id,
    required this.eventId,
    required this.notificationType,
    required this.points,
    required this.title,
    required this.subtitle,
    required this.displayPriority,
    required Map<String, dynamic> payload,
    required this.seenAt,
    required this.displayedAt,
    required this.createdAt,
  }) : payload = Map.unmodifiable(payload);

  final String id;
  final String? eventId;

  /// Dynamic notification type supplied by the backend.
  final String notificationType;

  final int points;

  final String? title;
  final String? subtitle;

  final int displayPriority;

  final Map<String, dynamic> payload;

  final DateTime? seenAt;
  final DateTime? displayedAt;

  final DateTime createdAt;

  factory GamificationNotification.fromJson(Map<String, dynamic> json) {
    return GamificationNotification(
      id: _requiredString(json['id'], 'id'),
      eventId: _nullableString(json['event_id']),
      notificationType: _requiredString(
        json['notification_type'],
        'notification_type',
      ).toLowerCase(),
      points: NumberConversionService.toInt(json['points']),
      title: _nullableString(json['title']),
      subtitle: _nullableString(json['subtitle']),
      displayPriority: NumberConversionService.toInt(json['display_priority']),
      payload: _asMap(json['payload']),
      seenAt: _nullableDateTime(json['seen_at']),
      displayedAt: _nullableDateTime(json['displayed_at']),
      createdAt: _requiredDateTime(json['created_at'], 'created_at'),
    );
  }

  bool get hasPoints => points != 0;

  bool get hasBeenDisplayed => displayedAt != null;

  bool get hasBeenSeen => seenAt != null;

  bool get isPendingDisplay => displayedAt == null;

  static String _requiredString(dynamic value, String field) {
    final result = value?.toString().trim();

    if (result == null || result.isEmpty) {
      throw FormatException('GamificationNotification.$field is required.');
    }

    return result;
  }

  static String? _nullableString(dynamic value) {
    final result = value?.toString().trim();

    if (result == null || result.isEmpty) {
      return null;
    }

    return result;
  }

  static DateTime _requiredDateTime(dynamic value, String field) {
    final raw = _nullableString(value);

    if (raw == null) {
      throw FormatException('GamificationNotification.$field is required.');
    }

    final parsed = DateTime.tryParse(raw);

    if (parsed == null) {
      throw FormatException('GamificationNotification.$field is invalid.');
    }

    return parsed.toLocal();
  }

  static DateTime? _nullableDateTime(dynamic value) {
    final raw = _nullableString(value);

    if (raw == null) {
      return null;
    }

    return DateTime.tryParse(raw)?.toLocal();
  }

  static Map<String, dynamic> _asMap(dynamic value) {
    if (value is Map) {
      return Map<String, dynamic>.from(value);
    }

    return const {};
  }
}
