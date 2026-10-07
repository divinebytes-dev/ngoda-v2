import 'package:ngoda/data_models/gamification/loyalty/transaction_loyalty_result.dart';
import 'package:ngoda/data_models/loan/loan_preview.dart';
import 'package:ngoda/ui/enums/enums.dart';

class LoanTransactionState {
  static const _unset = Object();

  final double amount;
  final String? reference;
  final BorrowStep step;
  final LoanPreview? preview;

  final double availableBalance;
  final double remainingBalance;

  final double principalBalance;
  final double interestBalance;

  final double collateralBalance;
  final double collateralReleased;
  final double collateralRemaining;

  final double interestPaid;
  final double principalPaid;

  final double remainingPrincipal;
  final double remainingInterest;

  final bool isValid;
  final bool isLoading;
  final String? error;
  final TransactionLoyaltyResult? loyaltyResult;

  const LoanTransactionState({
    this.amount = 0,
    this.principalBalance = 0,
    this.interestBalance = 0,
    this.interestPaid = 0,
    this.principalPaid = 0,
    this.remainingPrincipal = 0,
    this.remainingInterest = 0,
    this.collateralBalance = 0,
    this.collateralReleased = 0,
    this.collateralRemaining = 0,
    this.availableBalance = 0,
    this.remainingBalance = 0,
    this.isValid = false,
    this.preview,
    this.reference,
    this.isLoading = false,
    this.step = BorrowStep.input,
    this.error,
    this.loyaltyResult,
  });

  double get totalBalance => principalBalance + interestBalance;

  LoanTransactionState copyWith({
    double? amount,
    double? principalBalance,
    double? interestBalance,
    double? interestPaid,
    double? principalPaid,
    double? remainingPrincipal,
    double? remainingInterest,
    double? collateralBalance,
    double? collateralReleased,
    double? collateralRemaining,
    double? availableBalance,
    double? remainingBalance,
    Object? preview = _unset,
    BorrowStep? step,
    bool? isLoading,
    bool? isValid,
    Object? error = _unset,
    Object? reference = _unset,
    Object? loyaltyResult = _unset,
  }) {
    return LoanTransactionState(
      amount: amount ?? this.amount,
      principalBalance: principalBalance ?? this.principalBalance,
      interestBalance: interestBalance ?? this.interestBalance,
      interestPaid: interestPaid ?? this.interestPaid,
      principalPaid: principalPaid ?? this.principalPaid,
      remainingPrincipal: remainingPrincipal ?? this.remainingPrincipal,
      remainingInterest: remainingInterest ?? this.remainingInterest,
      collateralBalance: collateralBalance ?? this.collateralBalance,
      collateralReleased: collateralReleased ?? this.collateralReleased,
      collateralRemaining: collateralRemaining ?? this.collateralRemaining,
      availableBalance: availableBalance ?? this.availableBalance,
      remainingBalance: remainingBalance ?? this.remainingBalance,
      preview: identical(preview, _unset)
          ? this.preview
          : preview as LoanPreview?,
      step: step ?? this.step,
      isLoading: isLoading ?? this.isLoading,
      isValid: isValid ?? this.isValid,
      reference: identical(reference, _unset)
          ? this.reference
          : reference as String?,
      error: identical(error, _unset) ? this.error : error as String?,
      loyaltyResult: identical(loyaltyResult, _unset)
          ? this.loyaltyResult
          : loyaltyResult as TransactionLoyaltyResult?,
    );
  }
}
