import 'package:ngoda/services/number_conversion_service.dart';

class TaxSettlementItem {
  const TaxSettlementItem({
    required this.id,
    required this.period,
    required this.fiscalYear,
    required this.batchId,
    required this.transactionType,
    required this.currencyCode,
    required this.totalAmount,
    required this.totalTaxAmount,
    required this.status,
    this.paidAt,
    this.errorMessage,
  });

  final String id;
  final int period;
  final int fiscalYear;

  final String batchId;
  final String transactionType;
  final String currencyCode;

  final double totalAmount;
  final double totalTaxAmount;

  final String status;

  final DateTime? paidAt;
  final String? errorMessage;

  factory TaxSettlementItem.fromJson(Map<String, dynamic> json) {
    return TaxSettlementItem(
      id: json['id']?.toString() ?? '',
      period: NumberConversionService.toInt(json['period']),
      fiscalYear: NumberConversionService.toInt(json['fiscal_year']),
      batchId: json['batch_id']?.toString() ?? '',
      transactionType: _normalize(json['transaction_type']),
      currencyCode: _normalize(json['currency_code']),
      totalAmount: NumberConversionService.toDouble(json['gross_amount']),
      totalTaxAmount: NumberConversionService.toDouble(json['tax_amount']),
      status: _normalize(json['status']),
      paidAt: _nullableDateTime(json['paid_at']),
      errorMessage: _nullableString(json['error_message']),
    );
  }

  static String _normalize(dynamic value) {
    return value?.toString().trim().toLowerCase() ?? '';
  }

  static String? _nullableString(dynamic value) {
    final normalized = value?.toString().trim();

    return normalized == null || normalized.isEmpty ? null : normalized;
  }

  static DateTime? _nullableDateTime(dynamic value) {
    if (value == null) {
      return null;
    }

    return DateTime.tryParse(value.toString());
  }
}
