import 'package:ngoda/data_models/customer/loan_gold_balance.dart';

class LoanGoldSummary {
  const LoanGoldSummary({
    required this.total,
    required this.locked,
    required this.available,
  });

  final LoanGoldBalance total;
  final LoanGoldBalance locked;
  final LoanGoldBalance available;

  factory LoanGoldSummary.fromJson(Map<String, dynamic> json) {
    return LoanGoldSummary(
      total: LoanGoldBalance.fromJson(_asMap(json['total'])),
      locked: LoanGoldBalance.fromJson(_asMap(json['locked'])),
      available: LoanGoldBalance.fromJson(_asMap(json['available'])),
    );
  }

  bool get hasGold => total.grams > 0;

  bool get hasLockedGold => locked.grams > 0;

  bool get hasAvailableGold => available.grams > 0;

  double get availablePercent {
    if (total.grams <= 0) {
      return 0;
    }

    return (available.grams / total.grams) * 100;
  }

  double get lockedPercent {
    if (total.grams <= 0) {
      return 0;
    }

    return (locked.grams / total.grams) * 100;
  }

  static Map<String, dynamic> _asMap(dynamic value) {
    if (value is Map) {
      return Map<String, dynamic>.from(value);
    }

    return const {};
  }
}
