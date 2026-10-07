import 'package:ngoda/data_models/currency/currency.dart';

class TreasuryTransactionState {
  const TreasuryTransactionState({
    this.id,
    this.isLoading = false,
    this.isValid = false,
    this.error,
    this.reference,
    this.currency,
    this.email = '',
    this.amount = 0.0,
    this.remaining = 0.0,
    this.totalDebit = 0.0,
    this.balance = 0.0,
  });

  final String? id;
  final bool isLoading;
  final bool isValid;
  final String? error;
  final String? reference;
  final Currency? currency;
  final String email;
  final double amount;
  final double remaining;
  final double totalDebit;
  final double balance;

  TreasuryTransactionState copyWith({
    String? id,
    bool? isLoading,
    bool? isValid,
    String? error,
    String? reference,
    Currency? currency,
    String? email,
    double? amount,
    double? remaining,
    double? totalDebit,
    double? balance,
  }) {
    return TreasuryTransactionState(
      id: id ?? this.id,
      isLoading: isLoading ?? this.isLoading,
      isValid: isValid ?? this.isValid,
      error: error,
      reference: reference ?? this.reference,
      currency: currency ?? this.currency,
      email: email ?? this.email,
      amount: amount ?? this.amount,
      remaining: remaining ?? this.remaining,
      totalDebit: totalDebit ?? this.totalDebit,
      balance: balance ?? this.balance,
    );
  }
}
