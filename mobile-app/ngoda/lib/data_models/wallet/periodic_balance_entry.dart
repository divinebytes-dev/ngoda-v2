import 'package:ngoda/services/number_conversion_service.dart';

class PeriodicBalanceEntry {
  const PeriodicBalanceEntry({
    required this.documentNumber,
    required this.transactionType,
    required this.debit,
    required this.credit,
    required this.runningBalance,
    required this.createdAt,
  });

  final String documentNumber;

  /// Dynamic backend transaction type.
  final String transactionType;

  final double debit;
  final double credit;

  final double runningBalance;

  final DateTime createdAt;

  factory PeriodicBalanceEntry.fromJson(Map<String, dynamic> json) {
    return PeriodicBalanceEntry(
      documentNumber: _requiredString(
        json['document_number'],
        'document_number',
      ),
      transactionType: _requiredString(
        json['transaction_type'],
        'transaction_type',
      ).toLowerCase(),
      debit: NumberConversionService.toDouble(json['debit']),
      credit: NumberConversionService.toDouble(json['credit']),
      runningBalance: NumberConversionService.toDouble(json['running_balance']),
      createdAt: _requiredDateTime(json['created_at'], 'created_at'),
    );
  }

  bool get isDebit => debit > 0;

  bool get isCredit => credit > 0;

  double get movement => credit - debit;

  bool get hasMovement => debit != 0 || credit != 0;
}

String _requiredString(dynamic value, String field) {
  final result = value?.toString().trim();

  if (result == null || result.isEmpty) {
    throw FormatException(
      'PeriodicBalanceEntry.'
      '$field is required.',
    );
  }

  return result;
}

DateTime _requiredDateTime(dynamic value, String field) {
  final raw = value?.toString().trim();

  if (raw == null || raw.isEmpty) {
    throw FormatException(
      'PeriodicBalanceEntry.'
      '$field is required.',
    );
  }

  final parsed = DateTime.tryParse(raw);

  if (parsed == null) {
    throw FormatException(
      'PeriodicBalanceEntry.'
      '$field is invalid.',
    );
  }

  return parsed;
}
