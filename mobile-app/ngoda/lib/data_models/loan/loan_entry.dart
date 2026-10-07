import 'package:ngoda/services/number_conversion_service.dart';

class LoanEntry {
  const LoanEntry({
    required this.createdAt,
    required this.entryType,
    required this.debitPrincipal,
    required this.creditPrincipal,
    required this.debitInterest,
    required this.creditInterest,
    required this.accrualDate,
  });

  final DateTime createdAt;

  /// Dynamic backend entry type.
  final String entryType;

  final double debitPrincipal;
  final double creditPrincipal;

  final double debitInterest;
  final double creditInterest;

  final DateTime? accrualDate;

  factory LoanEntry.fromJson(Map<String, dynamic> json) {
    return LoanEntry(
      createdAt: _requiredDateTime(json['created_at'], 'LoanEntry.createdAt'),
      entryType: json['entry_type']?.toString().trim().toLowerCase() ?? '',
      debitPrincipal: NumberConversionService.toDouble(json['debit_principal']),
      creditPrincipal: NumberConversionService.toDouble(
        json['credit_principal'],
      ),
      debitInterest: NumberConversionService.toDouble(json['debit_interest']),
      creditInterest: NumberConversionService.toDouble(json['credit_interest']),
      accrualDate: _nullableDateTime(json['accrual_date']),
    );
  }

  double get netPrincipal => debitPrincipal - creditPrincipal;

  double get netInterest => debitInterest - creditInterest;

  bool get hasPrincipalMovement => debitPrincipal != 0 || creditPrincipal != 0;

  bool get hasInterestMovement => debitInterest != 0 || creditInterest != 0;

  static DateTime _requiredDateTime(dynamic value, String field) {
    final raw = value?.toString().trim();

    if (raw == null || raw.isEmpty) {
      throw FormatException('$field is required.');
    }

    return DateTime.parse(raw);
  }

  static DateTime? _nullableDateTime(dynamic value) {
    final raw = value?.toString().trim();

    if (raw == null || raw.isEmpty) {
      return null;
    }

    return DateTime.tryParse(raw);
  }
}
