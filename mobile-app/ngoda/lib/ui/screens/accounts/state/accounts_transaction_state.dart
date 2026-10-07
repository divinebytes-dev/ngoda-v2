import 'package:ngoda/data_models/currency/currency.dart';

class AccountsTransactionState {
  final double amount;
  final double remaining;
  final double totalDebit;
  final double balance;
  final bool isValid;
  final bool isLoading;
  final Currency? currency;

  final DateTime? startDate;
  final DateTime? endDate;

  final String? error;

  const AccountsTransactionState({
    this.amount = 0,
    this.balance = 0,
    this.totalDebit = 0,
    this.isValid = false,
    this.isLoading = false,
    this.remaining = 0,
    this.currency,
    this.startDate,
    this.endDate,
    this.error,
  });

  AccountsTransactionState copyWith({
    double? amount,
    double? balance,
    double? totalDebit,
    double? remaining,
    bool? isValid,
    bool? isLoading,
    Currency? currency,
    DateTime? startDate,
    DateTime? endDate,
    String? error,
  }) {
    return AccountsTransactionState(
      amount: amount ?? this.amount,
      currency: currency ?? this.currency,
      remaining: remaining ?? this.remaining,
      totalDebit: totalDebit ?? this.totalDebit,
      balance: balance ?? this.balance,
      isValid: isValid ?? this.isValid,
      startDate: startDate ?? this.startDate,
      endDate: endDate ?? this.endDate,
      isLoading: isLoading ?? this.isLoading,
      error: error,
    );
  }
}
