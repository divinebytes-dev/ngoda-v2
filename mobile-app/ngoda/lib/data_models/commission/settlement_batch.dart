import 'package:ngoda/services/number_conversion_service.dart';

class SettlementBatch {
  const SettlementBatch({
    required this.id,
    required this.period,
    required this.fiscalYear,
    required this.documentNumber,
    required this.currencyCode,
    required this.startDate,
    required this.endDate,
    required this.totalAgents,
    required this.totalAmount,
    required this.status,
    required this.createdBy,
    required this.createdAt,
    this.reference,
    this.approvedBy,
    this.approvedAt,
    this.paidAt,
    this.errorMessage,
  });

  final String id;

  final int period;
  final int fiscalYear;

  final String documentNumber;
  final String? reference;

  final String currencyCode;

  final DateTime startDate;
  final DateTime endDate;

  final int totalAgents;
  final double totalAmount;

  final String status;

  final String createdBy;
  final String? approvedBy;

  final DateTime createdAt;
  final DateTime? approvedAt;
  final DateTime? paidAt;

  final String? errorMessage;

  factory SettlementBatch.fromJson(Map<String, dynamic> json) {
    return SettlementBatch(
      id: json['id']?.toString() ?? '',
      period: NumberConversionService.toInt(json['period']),
      fiscalYear: NumberConversionService.toInt(json['fiscal_year']),
      documentNumber: json['document_number']?.toString() ?? '',
      reference: _nullableString(json['reference']),
      currencyCode:
          json['currency_code']?.toString().trim().toLowerCase() ?? '',
      startDate: DateTime.parse(json['start_date'].toString()),
      endDate: DateTime.parse(json['end_date'].toString()),
      totalAgents: NumberConversionService.toInt(json['total_agents']),
      totalAmount: NumberConversionService.toDouble(json['total_amount']),
      status: json['status']?.toString().trim().toLowerCase() ?? '',
      createdBy: json['created_by']?.toString() ?? '',
      approvedBy: _nullableString(json['approved_by']),
      createdAt: DateTime.parse(json['created_at'].toString()),
      approvedAt: _nullableDateTime(json['approved_at']),
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
