import 'package:ngoda/services/number_conversion_service.dart';

class TaxSettlementBatch {
  const TaxSettlementBatch({
    required this.id,
    required this.period,
    required this.fiscalYear,
    required this.documentNumber,
    required this.currencyCode,
    required this.startDate,
    required this.endDate,
    required this.totalAmount,
    required this.status,
    required this.createdBy,
    required this.createdAt,
    this.approvedBy,
    this.approvedAt,
    this.paidAt,
    this.errorMessage,
  });

  final String id;
  final int period;
  final int fiscalYear;

  final String documentNumber;
  final String currencyCode;

  final DateTime startDate;
  final DateTime endDate;

  final double totalAmount;

  final String status;

  final String createdBy;
  final String? approvedBy;

  final DateTime createdAt;
  final DateTime? approvedAt;
  final DateTime? paidAt;

  final String? errorMessage;

  factory TaxSettlementBatch.fromJson(Map<String, dynamic> json) {
    return TaxSettlementBatch(
      id: json['id']?.toString() ?? '',
      period: NumberConversionService.toInt(json['period']),
      fiscalYear: NumberConversionService.toInt(json['fiscal_year']),
      documentNumber: json['document_number']?.toString() ?? '',
      currencyCode: _normalize(json['currency_code']),
      startDate: DateTime.parse(json['start_date'].toString()),
      endDate: DateTime.parse(json['end_date'].toString()),
      totalAmount: NumberConversionService.toDouble(json['total_amount']),
      status: _normalize(json['status']),
      createdBy: json['created_by']?.toString() ?? '',
      approvedBy: _nullableString(json['approved_by']),
      createdAt: DateTime.parse(json['created_at'].toString()),
      approvedAt: _nullableDateTime(json['approved_at']),
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

    final normalized = value.toString().trim();

    if (normalized.isEmpty) {
      return null;
    }

    return DateTime.tryParse(normalized);
  }
}
