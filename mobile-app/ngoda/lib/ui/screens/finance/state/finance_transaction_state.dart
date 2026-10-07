import 'package:ngoda/data_models/currency/currency.dart';
import 'package:ngoda/ui/enums/enums.dart';

class FinanceTransactionState {
  const FinanceTransactionState({
    this.type,
    this.reference,
    this.feeAmount = 0,
    this.feePercent = 0,
    this.amount = 0,
    this.remaining = 0,
    this.totalDebit = 0,
    this.balance = 0,
    this.isValid = false,
    this.currency,
    this.email = '',
    this.grams = 0,
    this.price = 0,
    this.serialNumber = '',
    this.isLoading = false,
    this.error,
  });

  final FinanceTransactionType? type;

  final String? reference;

  final double feeAmount;
  final double feePercent;
  final double amount;
  final double remaining;
  final double totalDebit;
  final double balance;
  final bool isValid;

  final Currency? currency;

  final String email;

  final double grams;
  final double price;
  final String serialNumber;

  final bool isLoading;
  final String? error;

  FinanceTransactionState copyWith({
    FinanceTransactionType? type,
    String? reference,
    double? feeAmount,
    double? feePercent,
    double? amount,
    double? remaining,
    double? totalDebit,
    double? balance,
    bool? isValid,
    Currency? currency,
    String? email,
    double? grams,
    double? price,
    String? serialNumber,
    bool? isLoading,
    String? error,
  }) {
    return FinanceTransactionState(
      type: type ?? this.type,
      reference: reference ?? this.reference,
      feeAmount: feeAmount ?? this.feeAmount,
      feePercent: feePercent ?? this.feePercent,
      amount: amount ?? this.amount,
      remaining: remaining ?? this.remaining,
      totalDebit: totalDebit ?? this.totalDebit,
      balance: balance ?? this.balance,
      isValid: isValid ?? this.isValid,
      currency: currency ?? this.currency,
      email: email ?? this.email,
      grams: grams ?? this.grams,
      price: price ?? this.price,
      serialNumber: serialNumber ?? this.serialNumber,
      isLoading: isLoading ?? this.isLoading,
      error: error,
    );
  }
}
