import 'package:ngoda/data_models/financial-statements/trial-balance/trial_balance_account.dart';
import 'package:ngoda/data_models/financial-statements/trial-balance/trial_balance_total.dart';

class TrialBalanceCurrency {
  TrialBalanceCurrency({
    required List<TrialBalanceAccount> accounts,
    required this.total,
  }) : accounts = List.unmodifiable(accounts);

  final List<TrialBalanceAccount> accounts;

  final TrialBalanceTotal total;

  factory TrialBalanceCurrency.fromJson(Map<String, dynamic> json) {
    return TrialBalanceCurrency(
      accounts: _parseAccounts(json['accounts']),
      total: TrialBalanceTotal.fromJson(_asMap(json['totals'])),
    );
  }

  /// Backend trial-balance result.
  bool get isBalanced => total.balanced;

  /// Sum calculated from the individual
  /// account rows.
  double get computedDebit {
    return accounts.fold(0.0, (sum, account) => sum + account.debit);
  }

  /// Sum calculated from the individual
  /// account rows.
  double get computedCredit {
    return accounts.fold(0.0, (sum, account) => sum + account.credit);
  }

  double get computedDifference => computedDebit - computedCredit;

  bool get computedBalanced => computedDifference.abs() <= 0.000001;

  /// Checks that the account rows agree
  /// with the totals returned by the backend.
  bool get totalsMatchAccounts {
    return (computedDebit - total.totalDebit).abs() <= 0.000001 &&
        (computedCredit - total.totalCredit).abs() <= 0.000001;
  }

  bool get isEmpty => accounts.isEmpty;

  bool get isNotEmpty => accounts.isNotEmpty;

  static List<TrialBalanceAccount> _parseAccounts(dynamic value) {
    if (value is! List) {
      return const [];
    }

    return value
        .whereType<Map>()
        .map(
          (account) =>
              TrialBalanceAccount.fromJson(Map<String, dynamic>.from(account)),
        )
        .toList();
  }

  static Map<String, dynamic> _asMap(dynamic value) {
    if (value is Map) {
      return Map<String, dynamic>.from(value);
    }

    return const {};
  }
}
