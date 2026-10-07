import 'package:ngoda/services/number_conversion_service.dart';

class FinanceTransaction {
  const FinanceTransaction({
    required this.fiscalYear,
    required this.period,
    required this.createdAt,
    required this.documentNumber,
    required this.transactionType,
    required this.description,
    required this.grossAmount,
  });

  final int fiscalYear;
  final int period;

  final DateTime createdAt;

  final String documentNumber;
  final String transactionType;
  final String description;

  final double grossAmount;

  factory FinanceTransaction.fromJson(Map<String, dynamic> json) {
    return FinanceTransaction(
      fiscalYear: NumberConversionService.toInt(json['fiscal_year']),
      period: NumberConversionService.toInt(json['period']),
      createdAt: _parseRequiredDate(json['created_at']),
      documentNumber: json['document_number']?.toString().trim() ?? '',
      transactionType:
          json['transaction_type']?.toString().trim().toLowerCase() ?? '',
      description: json['description']?.toString().trim() ?? '',
      grossAmount: NumberConversionService.toDouble(json['gross_amount']),
    );
  }

  static DateTime _parseRequiredDate(dynamic value) {
    final raw = value?.toString().trim();

    if (raw == null || raw.isEmpty) {
      throw const FormatException('FinanceTransaction.created_at is required.');
    }

    return DateTime.parse(raw);
  }
}
