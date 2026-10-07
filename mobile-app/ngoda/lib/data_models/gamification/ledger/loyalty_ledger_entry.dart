import 'package:ngoda/data_models/gamification/ledger/loyalty_ledger_type.dart';
import 'package:ngoda/services/number_conversion_service.dart';

class LoyaltyLedgerEntry {
  LoyaltyLedgerEntry({
    required this.id,
    required this.eventId,
    required this.ledgerType,
    required this.eventType,
    required this.pointsDelta,
    required this.availableBalanceAfter,
    required this.tierPointsDelta,
    required this.tierBalanceAfter,
    required this.sourceReference,
    required this.description,
    required this.reversalOfLedgerId,
    required Map<String, dynamic> metadata,
    required this.createdAt,
  }) : metadata = Map.unmodifiable(metadata);

  final String id;
  final String? eventId;

  final LoyaltyLedgerType ledgerType;

  /// Dynamic backend event type.
  final String? eventType;

  final int pointsDelta;
  final int availableBalanceAfter;

  final int tierPointsDelta;
  final int tierBalanceAfter;

  final String? sourceReference;
  final String? description;
  final String? reversalOfLedgerId;

  final Map<String, dynamic> metadata;

  final DateTime createdAt;

  factory LoyaltyLedgerEntry.fromJson(Map<String, dynamic> json) {
    return LoyaltyLedgerEntry(
      id: _requiredString(json['id'], 'LoyaltyLedgerEntry.id'),
      eventId: _nullableString(json['event_id']),
      ledgerType: LoyaltyLedgerType.fromApiValue(json['ledger_type']),
      eventType: _nullableString(json['event_type']),
      pointsDelta: NumberConversionService.toInt(json['points_delta']),
      availableBalanceAfter: NumberConversionService.toInt(
        json['available_balance_after'],
      ),
      tierPointsDelta: NumberConversionService.toInt(json['tier_points_delta']),
      tierBalanceAfter: NumberConversionService.toInt(
        json['tier_balance_after'],
      ),
      sourceReference: _nullableString(json['source_reference']),
      description: _nullableString(json['description']),
      reversalOfLedgerId: _nullableString(json['reversal_of_ledger_id']),
      metadata: _asMap(json['metadata']),
      createdAt: _requiredDate(json['created_at']),
    );
  }

  bool get earnsPoints => pointsDelta > 0;

  bool get spendsPoints => pointsDelta < 0;

  static String _requiredString(dynamic value, String field) {
    final result = value?.toString().trim();

    if (result == null || result.isEmpty) {
      throw FormatException('$field is required.');
    }

    return result;
  }

  static String? _nullableString(dynamic value) {
    final result = value?.toString().trim();

    return result == null || result.isEmpty ? null : result;
  }

  static DateTime _requiredDate(dynamic value) {
    final raw = value?.toString().trim();

    if (raw == null || raw.isEmpty) {
      throw const FormatException('LoyaltyLedgerEntry.createdAt is required.');
    }

    return DateTime.parse(raw).toLocal();
  }

  static Map<String, dynamic> _asMap(dynamic value) {
    if (value is Map) {
      return Map<String, dynamic>.from(value);
    }

    return const {};
  }
}
