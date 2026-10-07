import 'package:ngoda/services/number_conversion_service.dart';

class WalletTransaction {
  const WalletTransaction({
    required this.createdAt,
    required this.transactionType,
    required this.debit,
    required this.credit,
    required this.runningBalance,
  });

  final DateTime createdAt;

  /// Dynamic backend transaction type.
  final String transactionType;

  final double debit;
  final double credit;

  final double runningBalance;

  factory WalletTransaction.fromJson(Map<String, dynamic> json) {
    return WalletTransaction(
      createdAt: _requiredDateTime(json['created_at']),
      transactionType:
          json['transaction_type']?.toString().trim().toLowerCase() ?? '',
      debit: NumberConversionService.toDouble(json['debit']),
      credit: NumberConversionService.toDouble(json['credit']),
      runningBalance: NumberConversionService.toDouble(json['running_balance']),
    );
  }

  double get movement => credit - debit;

  bool get isDebit => debit > 0;

  bool get isCredit => credit > 0;

  bool get hasMovement => debit != 0 || credit != 0;
}

DateTime _requiredDateTime(dynamic value) {
  final raw = value?.toString().trim();

  if (raw == null || raw.isEmpty) {
    throw const FormatException(
      'WalletTransaction.created_at '
      'is required.',
    );
  }

  final parsed = DateTime.tryParse(raw);

  if (parsed == null) {
    throw const FormatException(
      'WalletTransaction.created_at '
      'is invalid.',
    );
  }

  return parsed;
}
