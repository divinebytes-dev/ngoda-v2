import 'package:ngoda/base/base_transaction_state.dart';
import 'package:ngoda/data_models/currency/currency.dart';
import 'package:ngoda/data_models/fee/cash_transfer_fee_configuration.dart';
import 'package:ngoda/data_models/gamification/loyalty/transaction_loyalty_result.dart';
import 'package:ngoda/ui/enums/enums.dart';

class WalletTransactionState extends BaseTransactionState {
  static const Object _unset = Object();

  final String? reference;

  final double amount;
  final double remaining;
  final double totalDebit;
  final double balance;

  final bool isValid;

  final Currency? currency;

  final double grossAmount;
  final double feeAmount;
  final double taxAmount;
  final double feePercent;
  final double taxPercent;

  final String? identifier;

  final bool isLoading;
  final String? error;

  final int feePoints;
  final int availablePoints;

  final bool canPayWithPoints;
  final bool paymentFeeContribution;

  final FeePaymentMethod feePaymentMethod;

  final TapPaymentState tapPaymentState;

  final CashTransferFeeConfiguration? configuration;

  final TransactionLoyaltyResult? loyaltyResult;

  const WalletTransactionState({
    this.reference,
    this.amount = 0,
    this.remaining = 0,
    this.totalDebit = 0,
    this.balance = 0,
    this.isValid = false,
    this.currency,
    this.grossAmount = 0,
    this.feeAmount = 0,
    this.taxAmount = 0,
    this.feePercent = 0,
    this.taxPercent = 0,
    this.identifier,
    this.isLoading = false,
    this.error,
    this.feePoints = 0,
    this.availablePoints = 0,
    this.canPayWithPoints = false,
    this.paymentFeeContribution = true,
    this.feePaymentMethod = FeePaymentMethod.cash,
    this.tapPaymentState = TapPaymentState.waiting,
    this.configuration,
    this.loyaltyResult,
    super.transactionStatus = TransactionStatus.waiting,
  });

  WalletTransactionState copyWith({
    Object? reference = _unset,
    double? amount,
    double? remaining,
    double? totalDebit,
    double? balance,
    bool? isValid,
    Object? currency = _unset,
    double? grossAmount,
    double? feeAmount,
    double? taxAmount,
    double? feePercent,
    double? taxPercent,
    Object? identifier = _unset,
    bool? isLoading,
    Object? error = _unset,
    int? feePoints,
    int? availablePoints,
    bool? canPayWithPoints,
    bool? paymentFeeContribution,
    FeePaymentMethod? feePaymentMethod,
    TransactionStatus? transactionStatus,
    TapPaymentState? tapPaymentState,
    Object? configuration = _unset,
    Object? loyaltyResult = _unset,
  }) {
    final effectiveCanPayWithPoints = canPayWithPoints ?? this.canPayWithPoints;

    final requestedFeePaymentMethod = feePaymentMethod ?? this.feePaymentMethod;

    final effectiveFeePaymentMethod =
        requestedFeePaymentMethod == FeePaymentMethod.points &&
            !effectiveCanPayWithPoints
        ? FeePaymentMethod.cash
        : requestedFeePaymentMethod;

    return WalletTransactionState(
      reference: identical(reference, _unset)
          ? this.reference
          : reference as String?,
      amount: amount ?? this.amount,
      remaining: remaining ?? this.remaining,
      totalDebit: totalDebit ?? this.totalDebit,
      balance: balance ?? this.balance,
      isValid: isValid ?? this.isValid,
      currency: identical(currency, _unset)
          ? this.currency
          : currency as Currency?,
      grossAmount: grossAmount ?? this.grossAmount,
      feeAmount: feeAmount ?? this.feeAmount,
      taxAmount: taxAmount ?? this.taxAmount,
      feePercent: feePercent ?? this.feePercent,
      taxPercent: taxPercent ?? this.taxPercent,
      identifier: identical(identifier, _unset)
          ? this.identifier
          : identifier as String?,
      isLoading: isLoading ?? this.isLoading,
      error: identical(error, _unset) ? this.error : error as String?,
      feePoints: feePoints ?? this.feePoints,
      availablePoints: availablePoints ?? this.availablePoints,
      canPayWithPoints: effectiveCanPayWithPoints,
      paymentFeeContribution:
          paymentFeeContribution ?? this.paymentFeeContribution,
      feePaymentMethod: effectiveFeePaymentMethod,
      tapPaymentState: tapPaymentState ?? this.tapPaymentState,
      configuration: identical(configuration, _unset)
          ? this.configuration
          : configuration as CashTransferFeeConfiguration?,
      loyaltyResult: identical(loyaltyResult, _unset)
          ? this.loyaltyResult
          : loyaltyResult as TransactionLoyaltyResult?,
      transactionStatus: transactionStatus ?? this.transactionStatus,
    );
  }
}
