import 'package:ngoda/services/number_conversion_service.dart';

class JournalLine {
  const JournalLine({
    required this.id,
    required this.period,
    required this.fiscalYear,
    required this.lineNumber,
    required this.documentNumber,
    required this.transactionType,
    required this.currencyCode,
    required this.glAccountCode,
    required this.glAccountName,
    required this.debit,
    required this.credit,
    required this.createdAt,
  });

  final String id;

  final int period;
  final int fiscalYear;

  final String lineNumber;

  final String documentNumber;
  final String transactionType;

  final String currencyCode;

  final String glAccountCode;
  final String glAccountName;

  final double debit;
  final double credit;

  final DateTime createdAt;

  factory JournalLine.fromJson(Map<String, dynamic> json) {
    return JournalLine(
      id: json['id']?.toString().trim() ?? '',
      period: NumberConversionService.toInt(json['period']),
      fiscalYear: NumberConversionService.toInt(json['fiscal_year']),
      lineNumber: json['line_number']?.toString().trim() ?? '',
      documentNumber: json['document_number']?.toString().trim() ?? '',
      transactionType:
          json['transaction_type']?.toString().trim().toLowerCase() ?? '',
      currencyCode:
          json['currency_code']?.toString().trim().toLowerCase() ?? '',
      glAccountCode: json['gl_account_code']?.toString().trim() ?? '',
      glAccountName: json['gl_account_name']?.toString().trim() ?? '',
      debit: NumberConversionService.toDouble(json['debit']),
      credit: NumberConversionService.toDouble(json['credit']),
      createdAt: _parseRequiredDate(json['created_at']),
    );
  }

  bool get isDebit => debit > 0;
  bool get isCredit => credit > 0;

  static DateTime _parseRequiredDate(dynamic value) {
    final raw = value?.toString().trim();

    if (raw == null || raw.isEmpty) {
      throw const FormatException('JournalLine.created_at is required.');
    }

    return DateTime.parse(raw);
  }
}
