import 'package:ngoda/data_models/gamification/loyalty/transaction_loyalty_result.dart';
import 'package:ngoda/data_models/gold/gold_calculation_result.dart';
import 'package:ngoda/ui/enums/enums.dart';

class GoldTransactionState {
  static const _unset = Object();

  final double amount;
  final String email;
  final String currency;
  final String? reference;

  final GoldTransactionType transactionType;
  final InputMode inputMode;

  final double goldPrice;
  final double feeRate;
  final double spreadRate;

  final double totalDebit;
  final double remaining;
  final double balance;

  final GoldCalculationResult? result;
  final TransactionLoyaltyResult? loyaltyResult;

  final bool isLoading;
  final bool isValid;
  final String? error;

  const GoldTransactionState({
    this.amount = 0.0,
    this.email = '',
    this.currency = 'USD',
    this.reference,
    this.transactionType = GoldTransactionType.buy,
    this.inputMode = InputMode.fiat,
    this.goldPrice = 0,
    this.feeRate = 0,
    this.spreadRate = 0,
    this.totalDebit = 0,
    this.remaining = 0,
    this.balance = 0,
    this.result,
    this.loyaltyResult,
    this.isLoading = false,
    this.isValid = false,
    this.error,
  });

  GoldTransactionState copyWith({
    double? amount,
    String? email,
    String? currency,
    Object? reference = _unset,
    GoldTransactionType? transactionType,
    InputMode? inputMode,
    double? goldPrice,
    double? feeRate,
    double? spreadRate,
    double? totalDebit,
    double? remaining,
    double? balance,
    Object? result = _unset,
    Object? loyaltyResult = _unset,
    bool? isLoading,
    bool? isValid,
    Object? error = _unset,
  }) {
    return GoldTransactionState(
      amount: amount ?? this.amount,
      email: email ?? this.email,
      currency: currency ?? this.currency,
      reference: identical(reference, _unset)
          ? this.reference
          : reference as String?,
      transactionType: transactionType ?? this.transactionType,
      inputMode: inputMode ?? this.inputMode,
      goldPrice: goldPrice ?? this.goldPrice,
      feeRate: feeRate ?? this.feeRate,
      spreadRate: spreadRate ?? this.spreadRate,
      totalDebit: totalDebit ?? this.totalDebit,
      remaining: remaining ?? this.remaining,
      balance: balance ?? this.balance,
      result: identical(result, _unset)
          ? this.result
          : result as GoldCalculationResult?,
      loyaltyResult: identical(loyaltyResult, _unset)
          ? this.loyaltyResult
          : loyaltyResult as TransactionLoyaltyResult?,
      isLoading: isLoading ?? this.isLoading,
      isValid: isValid ?? this.isValid,
      error: identical(error, _unset) ? this.error : error as String?,
    );
  }
}
