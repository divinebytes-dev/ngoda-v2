import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ngoda/core/providers/analytics_service_provider.dart';
import 'package:ngoda/data_models/gamification/loyalty/transaction_loyalty_result.dart';
import 'package:ngoda/data_models/loan/loan_preview.dart';
import 'package:ngoda/services/performance_service.dart';
import 'package:ngoda/ui/enums/enums.dart';
import 'package:ngoda/ui/functions/get_current_user.dart';
import 'package:ngoda/ui/functions/get_signed_transaction.dart';
import 'package:ngoda/ui/screens/wallet/loan/service/loan_api_service_provider.dart';
import 'package:ngoda/ui/screens/wallet/loan/state/loan_transaction_state.dart';
import 'package:ngoda/ui/screens/customer/provider/customer_dashboard_provider.dart';
import 'package:uuid/uuid.dart';

class LoanTransactionNotifier extends Notifier<LoanTransactionState> {
  final PerformanceService performanceService = PerformanceService();

  @override
  LoanTransactionState build() {
    return const LoanTransactionState();
  }

  void initReference() {
    state = state.copyWith(
      reference: const Uuid().v4(),
      error: null,
      loyaltyResult: null,
    );
  }

  void init({
    required double principalBalance,
    required double interestBalance,
  }) {
    state = state.copyWith(
      principalBalance: principalBalance,
      interestBalance: interestBalance,
      remainingPrincipal: principalBalance,
      remainingInterest: interestBalance,
      error: null,
    );
  }

  void updateRepayAmount(double amount, {required double balance}) {
    final loanTotal = state.principalBalance + state.interestBalance;

    /*
     * Repayment cannot exceed:
     *
     * 1. the outstanding loan balance, or
     * 2. the available wallet balance.
     *
     * Negative/non-finite values become zero.
     */
    final requestedAmount = amount.isFinite && amount > 0 ? amount : 0.0;

    final availableBalance = balance.isFinite && balance > 0 ? balance : 0.0;

    var safeAmount = requestedAmount;

    if (safeAmount > loanTotal) {
      safeAmount = loanTotal;
    }

    if (safeAmount > availableBalance) {
      safeAmount = availableBalance;
    }

    var remainingAmount = safeAmount;

    /*
     * Loan repayment allocation:
     * interest first, then principal.
     */
    final interestPaid = remainingAmount >= state.interestBalance
        ? state.interestBalance
        : remainingAmount;

    remainingAmount -= interestPaid;

    final principalPaid = remainingAmount >= state.principalBalance
        ? state.principalBalance
        : remainingAmount;

    final remainingBalance = availableBalance - safeAmount;

    state = state.copyWith(
      amount: safeAmount,
      interestPaid: interestPaid,
      principalPaid: principalPaid,
      remainingInterest: state.interestBalance - interestPaid,
      remainingPrincipal: state.principalBalance - principalPaid,
      availableBalance: availableBalance,
      remainingBalance: remainingBalance,
      isValid:
          safeAmount > 0 &&
          safeAmount <= loanTotal &&
          safeAmount <= availableBalance,
      error: null,
    );
  }

  void updateCollateralAmount(double amount, {required double balance}) {
    /*
     * Preserve the existing collateral rule.
     *
     * We will verify the meaning of `balance`
     * against the collateral screen before
     * changing this calculation.
     */
    final remainingBalance = state.principalBalance - amount;

    state = state.copyWith(
      amount: amount,
      availableBalance: state.principalBalance,
      remainingBalance: remainingBalance,
      isValid: amount > 0 && amount >= balance,
      error: null,
    );
  }

  void resetAmountOnly() {
    state = state.copyWith(
      amount: 0,
      interestPaid: 0,
      principalPaid: 0,
      remainingInterest: state.interestBalance,
      remainingPrincipal: state.principalBalance,
      remainingBalance: state.availableBalance,
      isValid: false,
      error: null,
      loyaltyResult: null,
    );
  }

  void updateAmount(double amount) {
    final safeAmount = amount.isFinite && amount > 0 ? amount : 0.0;

    state = state.copyWith(
      amount: safeAmount,
      isValid: safeAmount > 0,
      error: null,
    );
  }

  Future<LoanPreview> previewLoan() async {
    final analytics = ref.read(analyticsServiceProvider);

    final parameters = <String, String>{
      'currency': 'usd',
      'amount': state.amount.toString(),
    };

    state = state.copyWith(
      isLoading: true,
      step: BorrowStep.preview,
      error: null,
      preview: null,
      loyaltyResult: null,
    );

    try {
      analytics.logTransactionStarted(
        transactionType: 'loan_preview',
        transactionData: parameters,
      );

      final api = ref.read(loanApiServiceProvider);

      final loanPreview = await performanceService.trace(
        'loan_preview',
        () async {
          return api.loanPreview(amount: state.amount);
        },
      );

      state = state.copyWith(
        preview: loanPreview,
        isLoading: false,

        /*
         * Preserve the existing flow:
         * successful preview advances to
         * processing.
         *
         * We will verify this BorrowStep
         * transition against the borrow
         * screen before changing it.
         */
        step: BorrowStep.processing,
        error: null,
      );

      analytics.logTransactionCompleted(
        transactionType: 'loan_preview',
        transactionData: parameters,
      );

      return loanPreview;
    } catch (error) {
      state = state.copyWith(isLoading: false, error: error.toString());

      analytics.logTransactionFailed(
        transactionType: 'loan_preview',
        transactionData: parameters,
      );

      rethrow;
    }
  }

  Future<void> executeBorrow() async {
    if (state.preview == null) {
      return;
    }

    final reference = state.reference;

    if (reference == null || reference.trim().isEmpty) {
      state = state.copyWith(error: 'Transaction reference is unavailable.');

      return;
    }

    final analytics = ref.read(analyticsServiceProvider);

    final parameters = <String, String>{
      'currency': 'usd',
      'amount': state.amount.toString(),
    };

    state = state.copyWith(
      isLoading: true,
      step: BorrowStep.processing,
      error: null,
      loyaltyResult: null,
    );

    try {
      /*
       * Preserve the existing analytics event
       * spelling for reporting compatibility.
       */
      analytics.logTransactionStarted(
        transactionType: 'loan_disbursment',
        transactionData: parameters,
      );

      final api = ref.read(loanApiServiceProvider);

      await performanceService.trace('loan_disbursement', () async {
        await api.borrow(amount: state.amount, reference: reference);
      });

      analytics.logTransactionCompleted(
        transactionType: 'loan_disbursment',
        transactionData: parameters,
      );

      /*
       * Borrowing changes the customer's
       * dashboard loan/wallet position.
       */
      ref.invalidate(customerDashboardProvider);

      state = state.copyWith(
        isLoading: false,
        step: BorrowStep.input,
        error: null,
      );
    } catch (error) {
      state = state.copyWith(isLoading: false, error: error.toString());

      analytics.logTransactionFailed(
        transactionType: 'loan_disbursment',
        transactionData: parameters,
      );

      rethrow;
    }
  }

  Future<void> repayLoan() async {
    final reference = state.reference;

    if (reference == null || reference.trim().isEmpty) {
      state = state.copyWith(error: 'Transaction reference is unavailable.');

      return;
    }

    if (!state.isValid || state.amount <= 0) {
      state = state.copyWith(error: 'Enter a valid repayment amount.');

      return;
    }

    final analytics = ref.read(analyticsServiceProvider);

    final parameters = <String, String>{
      'currency': 'usd',
      'amount': state.amount.toString(),
    };

    state = state.copyWith(isLoading: true, error: null, loyaltyResult: null);

    try {
      analytics.logTransactionStarted(
        transactionType: 'loan_repay',
        transactionData: parameters,
      );

      final api = ref.read(loanApiServiceProvider);

      TransactionLoyaltyResult? loyaltyResult;

      await performanceService.trace('loan_repay', () async {
        loyaltyResult = await api.repay(
          amount: state.amount,
          reference: reference,
        );
      });

      analytics.logTransactionCompleted(
        transactionType: 'loan_repay',
        transactionData: parameters,
      );

      ref.invalidate(customerDashboardProvider);

      state = state.copyWith(
        isLoading: false,
        error: null,
        loyaltyResult: loyaltyResult,
      );
    } catch (error) {
      state = state.copyWith(
        isLoading: false,
        error: error.toString(),
        loyaltyResult: null,
      );

      analytics.logTransactionFailed(
        transactionType: 'loan_repay',
        transactionData: parameters,
      );

      rethrow;
    }
  }

  Future<void> topupCollateral() async {
    final reference = state.reference;

    if (reference == null || reference.trim().isEmpty) {
      state = state.copyWith(error: 'Transaction reference is unavailable.');

      return;
    }

    if (!state.isValid || state.amount <= 0) {
      state = state.copyWith(error: 'Enter a valid collateral amount.');

      return;
    }

    final analytics = ref.read(analyticsServiceProvider);

    final parameters = <String, String>{
      'currency': 'gold',
      'amount': state.amount.toString(),
    };

    state = state.copyWith(isLoading: true, error: null, loyaltyResult: null);

    try {
      analytics.logTransactionStarted(
        transactionType: 'topup_collateral',
        transactionData: parameters,
      );

      final user = getCurrentUser();

      final signedTransaction = await getSignedTransaction(
        v: '00',
        reference: reference,
        identifier: user.userId!,
        amount: state.amount,
        feeAmount: 0.0,
        currency: 'gold',
      );

      final api = ref.read(loanApiServiceProvider);

      await performanceService.trace('topup_collateral', () async {
        await api.topupCollateral(
          transactionData: signedTransaction.transactionData,
        );
      });

      analytics.logTransactionCompleted(
        transactionType: 'topup_collateral',
        transactionData: parameters,
      );

      ref.invalidate(customerDashboardProvider);

      state = state.copyWith(isLoading: false, error: null);
    } catch (error) {
      state = state.copyWith(isLoading: false, error: error.toString());

      analytics.logTransactionFailed(
        transactionType: 'topup_collateral',
        transactionData: parameters,
      );

      rethrow;
    }
  }

  void resetToInput() {
    state = state.copyWith(
      preview: null,
      step: BorrowStep.input,
      isLoading: false,
      error: null,
      loyaltyResult: null,
    );
  }

  void reset() {
    state = const LoanTransactionState();

    initReference();
  }
}
