import 'package:ngoda/services/number_conversion_service.dart';

class SettlementItem {
  const SettlementItem({
    required this.id,
    required this.period,
    required this.fiscalYear,
    required this.batchId,
    required this.agentId,
    required this.currencyCode,
    required this.totalCommission,
    required this.totalWithdrawalVolume,
    required this.totalFeesGenerated,
    required this.status,
    this.paidAt,
    this.errorMessage,
  });

  final String id;

  final int period;
  final int fiscalYear;

  final String batchId;
  final String agentId;

  final String currencyCode;

  final double totalCommission;
  final double totalWithdrawalVolume;
  final double totalFeesGenerated;

  final String status;

  final DateTime? paidAt;
  final String? errorMessage;

  factory SettlementItem.fromJson(Map<String, dynamic> json) {
    return SettlementItem(
      id: json['id']?.toString() ?? '',
      period: NumberConversionService.toInt(json['period']),
      fiscalYear: NumberConversionService.toInt(json['fiscal_year']),
      batchId: json['batch_id']?.toString() ?? '',
      agentId: json['agent_id']?.toString() ?? '',
      currencyCode:
          json['currency_code']?.toString().trim().toLowerCase() ?? '',
      totalCommission: NumberConversionService.toDouble(
        json['total_commission'],
      ),
      totalWithdrawalVolume: NumberConversionService.toDouble(
        json['total_withdrawal_volume'],
      ),
      totalFeesGenerated: NumberConversionService.toDouble(
        json['total_fees_generated'],
      ),
      status: json['status']?.toString().trim().toLowerCase() ?? '',
      paidAt: _nullableDateTime(json['paid_at']),
      errorMessage: _nullableString(json['error_message']),
    );
  }

  static String? _nullableString(dynamic value) {
    final result = value?.toString().trim();

    return result == null || result.isEmpty ? null : result;
  }

  static DateTime? _nullableDateTime(dynamic value) {
    final text = _nullableString(value);

    return text == null ? null : DateTime.tryParse(text);
  }
}
