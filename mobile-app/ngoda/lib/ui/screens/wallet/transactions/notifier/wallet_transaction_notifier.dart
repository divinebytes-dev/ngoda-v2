import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';
import 'package:ngoda/core/providers/analytics_service_provider.dart';
import 'package:ngoda/data_models/currency/currency.dart';
import 'package:ngoda/data_models/fee/cash_transfer_fee_configuration.dart';
import 'package:ngoda/data_models/fee/fee_config.dart';
import 'package:ngoda/data_models/fee/transfer_fee_points_calculator.dart';
import 'package:ngoda/data_models/gamification/loyalty/transaction_loyalty_result.dart';
import 'package:ngoda/data_models/transaction/sender_approval.dart';
import 'package:ngoda/data_models/transaction/transaction_data.dart';
import 'package:ngoda/services/number_format_service.dart';
import 'package:ngoda/services/performance_service.dart';
import 'package:ngoda/ui/enums/enums.dart';
import 'package:ngoda/ui/functions/get_current_user.dart';
import 'package:ngoda/ui/functions/get_identifier_type.dart';
import 'package:ngoda/ui/functions/get_signed_transaction.dart';
import 'package:ngoda/ui/screens/wallet/transactions/service/wallet_api_service_provider.dart';
import 'package:ngoda/ui/screens/wallet/transactions/state/wallet_transaction_state.dart';
import 'package:uuid/uuid.dart';

class WalletTransactionNotifier extends Notifier<WalletTransactionState> {
  final logger = Logger('WalletTransactionNotifier');

  final performanceService = PerformanceService();

  @override
  WalletTransactionState build() {
    return const WalletTransactionState();
  }

  void initReference() {
    final reference = const Uuid().v4();
    final user = getCurrentUser();

    state = state.copyWith(
      reference: reference,
      identifier: user.userId,
      error: null,
      loyaltyResult: null,
    );

    logger.info(
      'new reference : ${state.reference} '
      'identifier ${state.identifier}',
    );
  }

  void setTransactionStatus(TransactionStatus status) {
    logger.info('Changing status to $status');

    state = state.copyWith(transactionStatus: status);
  }

  void initBalance(double balance, Currency? currency) {
    state = state.copyWith(
      balance: balance,
      currency: currency,
      remaining: balance - state.totalDebit,
    );
  }

  void updateCurrency(Currency value, Map<String, double> balances) {
    final balance = balances[value.code] ?? 0;

    final insufficient = state.amount > 0 && state.totalDebit > balance;

    final identifier = state.identifier?.trim() ?? '';

    final identifierError = validateIdentifier(identifier);

    final error = validateState(
      identifierValid: identifierError,
      insufficient: insufficient,
    );

    state = state.copyWith(
      currency: value,
      balance: balance,
      remaining: balance - state.totalDebit,
      error: error,
      isValid: identifierError == null && !insufficient && state.amount > 0,
    );
  }

  void updateVoucherCurrency(Currency value) {
    state = state.copyWith(
      currency: value,
      isValid: state.amount > 0 && state.reference != null,
      error: null,
    );
  }

  void setTapState(TapPaymentState tapState) {
    logger.info('TapPaymentState $tapState');

    state = state.copyWith(tapPaymentState: tapState);
  }

  void updateAmount(String value, double balance) {
    final amount = NumberFormatService.anyToDouble(value);

    final identifier = state.identifier?.trim() ?? '';

    final identifierError = validateIdentifier(identifier);

    if (amount <= 0) {
      state = state.copyWith(
        amount: 0,
        balance: balance,
        grossAmount: 0,
        feeAmount: 0,
        taxAmount: 0,
        totalDebit: 0,
        remaining: balance,
        isValid: false,
        error: identifierError,
      );

      return;
    }

    final totalDebit = amount;
    final remaining = balance - totalDebit;

    final insufficient = totalDebit > balance;

    final error = validateState(
      identifierValid: identifierError,
      insufficient: insufficient,
    );

    state = state.copyWith(
      amount: amount,
      balance: balance,
      grossAmount: amount,
      feeAmount: 0,
      taxAmount: 0,
      totalDebit: totalDebit,
      remaining: remaining,
      isValid: identifierError == null && !insufficient,
      error: error,
    );
  }

  void updateUserDepositAmount(String value) {
    final amount = NumberFormatService.anyToDouble(value);

    if (amount <= 0) {
      state = state.copyWith(
        amount: 0,
        grossAmount: 0,
        feeAmount: 0,
        taxAmount: 0,
        totalDebit: 0,
        isValid: false,
        error: null,
      );

      return;
    }

    state = state.copyWith(
      amount: amount,
      grossAmount: amount,
      totalDebit: amount,
      isValid: state.currency != null && state.reference != null,
      error: null,
    );
  }

  void updateUserDepositCurrency(Currency value, Map<String, double> balances) {
    final balance = balances[value.code] ?? 0;

    state = state.copyWith(
      currency: value,
      balance: balance,
      remaining: balance - state.totalDebit,
      isValid: state.amount > 0 && state.reference != null,
      error: null,
    );
  }

  void updateAmountReceive(String value, {required FeeConfig feeConfig}) {
    logger.info(
      'value $value config $feeConfig, '
      'state.currency ${state.currency} '
      'state.reference ${state.reference}',
    );

    final amount = NumberFormatService.anyToDouble(value.trim());

    if (amount <= 0) {
      state = state.copyWith(
        amount: 0,
        grossAmount: 0,
        feeAmount: 0,
        taxAmount: 0,
        totalDebit: 0,
        isValid: false,
        error: null,
      );

      return;
    }

    state = state.copyWith(
      amount: amount,
      grossAmount: amount,
      feeAmount: 0,
      taxAmount: 0,
      totalDebit: amount,
      isValid: state.currency != null && state.reference != null,
      error: null,
    );
  }

  void updateVoucherAmount(String value, {required FeeConfig feeConfig}) {
    final amount = NumberFormatService.anyToDouble(value.trim());

    if (amount <= 0) {
      state = state.copyWith(
        amount: 0,
        grossAmount: 0,
        feeAmount: 0,
        taxAmount: 0,
        totalDebit: 0,
        isValid: false,
        error: null,
      );

      return;
    }

    final isValid = state.currency != null && state.reference != null;

    logger.info(
      'amount $amount config $feeConfig, '
      'state.currency ${state.currency?.code} '
      'state.reference ${state.reference} '
      'isValid $isValid '
      'isLoading ${state.isLoading}',
    );

    state = state.copyWith(
      amount: amount,
      grossAmount: amount,
      feeAmount: 0,
      taxAmount: 0,
      totalDebit: amount,
      isValid: isValid,
      error: null,
    );
  }

  String? validateState({String? identifierValid, required bool insufficient}) {
    final errors = <String>[];

    if (identifierValid != null) {
      errors.add(identifierValid);
    }

    if (insufficient) {
      errors.add('Insufficient balance');
    }

    return errors.isEmpty ? null : errors.join('\n');
  }

  void updateAmountToDeposit(TransactionData data) {
    final reference = data.r.trim();
    final identifier = data.s.trim();

    final amount = data.a / 100;
    final fee = data.f / 100;
    final totalDebit = amount + fee;

    logger.info(
      'amount: $amount '
      'state.currency ${state.currency} '
      'reference: $reference',
    );

    state = state.copyWith(
      amount: amount,
      identifier: identifier,
      grossAmount: totalDebit,
      feeAmount: fee,
      taxAmount: 0,
      totalDebit: totalDebit,
      isValid: amount > 0 && state.currency != null && reference.isNotEmpty,
      reference: reference,
      loyaltyResult: null,
      error: null,
    );
  }

  void updateIdentifier(String value) {
    final identifier = value.trim();

    final identifierError = validateIdentifier(identifier);
    logger.info("identifierError :$identifierError");

    final insufficient = state.amount > 0 && state.totalDebit > state.balance;

    final error = validateState(
      identifierValid: identifierError,
      insufficient: insufficient,
    );

    state = state.copyWith(
      identifier: identifier,
      error: error,
      isValid: identifierError == null && !insufficient && state.amount > 0,
    );
  }

  void updateWithdrawAmount(
    String value, {
    required FeeConfig feeConfig,
    required FeeConfig taxConfig,
    required double balance,
  }) {
    logger.info('amount $value fee $feeConfig');

    final cleaned = value.replaceAll(',', '');

    final amount = NumberFormatService.anyToDouble(cleaned.trim());

    if (amount <= 0) {
      state = state.copyWith(
        amount: 0,
        balance: balance,
        grossAmount: 0,
        feePercent: feeConfig.percentage,
        taxPercent: taxConfig.percentage,
        feeAmount: 0,
        taxAmount: 0,
        totalDebit: 0,
        remaining: balance,
        isValid: false,
        error: null,
      );

      return;
    }

    final feeAmount = feeConfig.calculateFee(amount);

    final taxAmount = taxConfig.calculateFee(amount);

    final totalDebit = amount + feeAmount + taxAmount;

    final remaining = balance - totalDebit;

    final insufficient = totalDebit > balance;

    state = state.copyWith(
      amount: amount,
      balance: balance,
      feePercent: feeConfig.percentage,
      taxPercent: taxConfig.percentage,
      taxAmount: taxAmount,
      feeAmount: feeAmount,
      totalDebit: totalDebit,
      remaining: remaining,
      isValid: !insufficient,
      grossAmount: totalDebit,
      error: insufficient ? 'Insufficient balance' : null,
    );
  }

  void reset() {
    logger.info('Resetting state');

    state = const WalletTransactionState();
  }

  Future<void> cashDeposit(TransactionData transactionData) async {
    state = state.copyWith(isLoading: true, error: null, loyaltyResult: null);

    final analytics = ref.read(analyticsServiceProvider);

    final parameters = <String, String>{
      'currency': state.currency!.code,
      'amount': state.amount.toString(),
    };

    try {
      final signedTransaction = await getSignedTransaction(
        v: 'v1',
        reference: transactionData.r,
        identifier: transactionData.s,
        amount: state.amount,
        feeAmount: state.feeAmount,
        currency: state.currency!.code,
      );

      analytics.logTransactionStarted(
        transactionType: 'cash_deposit',
        transactionData: parameters,
      );

      final service = ref.read(walletApiServiceProvider);

      TransactionLoyaltyResult? loyaltyResult;

      await performanceService.trace('cash_deposit', () async {
        loyaltyResult = await service.cashDeposit(
          transaction: transactionData,
          approval: signedTransaction.senderApproval,
        );
      });

      state = state.copyWith(isLoading: false, loyaltyResult: loyaltyResult);

      analytics.logTransactionCompleted(
        transactionType: 'cash_deposit',
        transactionData: parameters,
      );
    } catch (_) {
      state = state.copyWith(isLoading: false, loyaltyResult: null);

      analytics.logTransactionFailed(
        transactionType: 'cash_deposit',
        transactionData: parameters,
      );

      rethrow;
    }
  }

  Future<void> creditAgentCashSettlement(
    TransactionData transactionData,
  ) async {
    state = state.copyWith(isLoading: true, error: null, loyaltyResult: null);

    final analytics = ref.read(analyticsServiceProvider);

    final parameters = <String, String>{
      'currency': state.currency!.code,
      'amount': state.amount.toString(),
    };

    try {
      final signedTransaction = await getSignedTransaction(
        v: 'v1',
        reference: transactionData.r,
        identifier: transactionData.s,
        amount: state.amount,
        feeAmount: state.feeAmount,
        currency: state.currency!.code,
      );

      analytics.logTransactionStarted(
        transactionType: 'credit_agent_cash_settlement',
        transactionData: parameters,
      );

      final service = ref.read(walletApiServiceProvider);

      await performanceService.trace('credit_agent_cash_settlement', () async {
        await service.creditAgentCashSettlement(
          transaction: transactionData,
          approval: signedTransaction.senderApproval,
        );
      });

      state = state.copyWith(isLoading: false);

      analytics.logTransactionCompleted(
        transactionType: 'credit_agent_cash_settlement',
        transactionData: parameters,
      );
    } catch (_) {
      state = state.copyWith(isLoading: false);

      analytics.logTransactionFailed(
        transactionType: 'credit_agent_cash_settlement',
        transactionData: parameters,
      );

      rethrow;
    }
  }

  Future<void> creditAgentCashDeposit(TransactionData transactionData) async {
    state = state.copyWith(isLoading: true, error: null, loyaltyResult: null);

    final analytics = ref.read(analyticsServiceProvider);

    final parameters = <String, String>{
      'currency': state.currency!.code,
      'amount': state.amount.toString(),
    };

    try {
      final signedTransaction = await getSignedTransaction(
        v: 'v1',
        reference: transactionData.r,
        identifier: transactionData.s,
        amount: state.amount,
        feeAmount: state.feeAmount,
        currency: state.currency!.code,
      );

      /*
       * This remains cash_deposit intentionally for now.
       *
       * The backend method is still the separate
       * creditAgentCashDeposit process. We should only
       * rename analytics/performance classification if
       * analytics reporting is intended to distinguish
       * these two deposit channels.
       */
      analytics.logTransactionStarted(
        transactionType: 'cash_deposit',
        transactionData: parameters,
      );

      final service = ref.read(walletApiServiceProvider);

      TransactionLoyaltyResult? loyaltyResult;

      await performanceService.trace('cash_deposit', () async {
        loyaltyResult = await service.creditAgentCashDeposit(
          transaction: transactionData,
          approval: signedTransaction.senderApproval,
        );
      });

      state = state.copyWith(isLoading: false, loyaltyResult: loyaltyResult);

      analytics.logTransactionCompleted(
        transactionType: 'cash_deposit',
        transactionData: parameters,
      );
    } catch (_) {
      state = state.copyWith(isLoading: false, loyaltyResult: null);

      analytics.logTransactionFailed(
        transactionType: 'cash_deposit',
        transactionData: parameters,
      );

      rethrow;
    }
  }

  Future<void> cashTransfer() async {
    state = state.copyWith(isLoading: true, error: null, loyaltyResult: null);

    final analytics = ref.read(analyticsServiceProvider);

    final parameters = <String, String>{
      'currency': state.currency!.code,
      'amount': state.amount.toString(),
    };

    analytics.logTransactionStarted(
      transactionType: 'cash_transfer',
      transactionData: parameters,
    );

    try {
      final signedTransaction = await getSignedTransaction(
        v: 'v2',
        reference: state.reference!,
        identifier: state.identifier!,
        amount: state.amount,
        feeAmount: state.feeAmount,
        currency: state.currency!.code,
      );

      final service = ref.read(walletApiServiceProvider);

      TransactionLoyaltyResult? loyaltyResult;

      await performanceService.trace('cash_transfer', () async {
        loyaltyResult = await service.cashTransfer(
          feePaymentMethod: state.feePaymentMethod.apiValue,
          transaction: signedTransaction.transactionData,
        );
      });

      state = state.copyWith(isLoading: false, loyaltyResult: loyaltyResult);

      analytics.logTransactionCompleted(
        transactionType: 'cash_transfer',
        transactionData: parameters,
      );
    } catch (_) {
      state = state.copyWith(isLoading: false, loyaltyResult: null);

      analytics.logTransactionFailed(
        transactionType: 'cash_transfer',
        transactionData: parameters,
      );

      rethrow;
    }
  }

  void updateCashTransferFeeConfiguration(
    CashTransferFeeConfiguration configuration,
  ) {
    if (identical(state.configuration, configuration)) {
      return;
    }

    state = state.copyWith(configuration: configuration);

    _recalculateCashTransfer();
  }

  void updateAvailablePoints(int availablePoints) {
    final safePoints = availablePoints > 0 ? availablePoints : 0;

    if (state.availablePoints == safePoints) {
      return;
    }

    state = state.copyWith(availablePoints: safePoints);

    _recalculateCashTransfer();
  }

  void updateFeePaymentMethod(FeePaymentMethod feePaymentMethod) {
    if (feePaymentMethod == FeePaymentMethod.points &&
        !state.canPayWithPoints) {
      return;
    }

    state = state.copyWith(feePaymentMethod: feePaymentMethod);

    _recalculateCashTransfer();
  }

  void updateSendAmount(
    String value, {
    FeeConfig? feeConfig,
    required double balance,
  }) {
    final cleaned = value.replaceAll(',', '');

    final amount = NumberFormatService.anyToDouble(cleaned);

    if (amount <= 0) {
      final identifier = state.identifier?.trim() ?? '';

      final identifierError = validateIdentifier(identifier);

      final error = validateState(
        identifierValid: identifierError,
        insufficient: false,
      );

      state = state.copyWith(
        amount: 0,
        balance: balance,
        grossAmount: 0,
        feePercent: feeConfig?.percentage ?? 0,
        feeAmount: 0,
        taxAmount: 0,
        feePoints: 0,
        canPayWithPoints: false,
        feePaymentMethod: FeePaymentMethod.cash,
        totalDebit: 0,
        remaining: balance,
        isValid: false,
        error: error,
      );

      return;
    }

    final feeAmount = feeConfig?.calculateFee(amount) ?? 0;

    state = state.copyWith(
      amount: amount,
      balance: balance,
      grossAmount: amount,
      feePercent: feeConfig?.percentage ?? 0,
      feeAmount: feeAmount,
    );

    _recalculateCashTransfer();
  }

  void _recalculateCashTransfer() {
    final identifier = state.identifier?.trim() ?? '';

    final identifierError = validateIdentifier(identifier);

    final amount = state.amount;
    final feeAmount = state.feeAmount;
    final configuration = state.configuration;
    final currency = state.currency;

    var feePoints = 0;
    var canPayWithPoints = false;

    if (amount > 0 &&
        feeAmount > 0 &&
        configuration != null &&
        currency != null &&
        currency.code.toLowerCase() != 'gold') {
      try {
        final calculator = TransferFeePointsCalculator(
          configuration: configuration,
        );

        final quote = calculator.calculate(
          feeAmount: feeAmount,
          currencyCode: currency.code,
          availablePoints: state.availablePoints,
        );

        feePoints = quote.pointsRequired;

        canPayWithPoints = quote.canPayWithPoints;
      } catch (_) {
        feePoints = 0;
        canPayWithPoints = false;
      }
    }

    final effectiveFeePaymentMethod =
        state.feePaymentMethod == FeePaymentMethod.points && canPayWithPoints
        ? FeePaymentMethod.points
        : FeePaymentMethod.cash;

    final cashFee = effectiveFeePaymentMethod == FeePaymentMethod.points
        ? 0.0
        : feeAmount;

    final totalDebit = amount + cashFee + state.taxAmount;

    final remaining = state.balance - totalDebit;

    final insufficient = totalDebit > state.balance;

    final error = validateState(
      identifierValid: identifierError,
      insufficient: insufficient,
    );

    state = state.copyWith(
      feePoints: feePoints,
      canPayWithPoints: canPayWithPoints,
      feePaymentMethod: effectiveFeePaymentMethod,
      totalDebit: totalDebit,
      remaining: remaining,
      grossAmount: totalDebit,
      isValid: identifierError == null && !insufficient && amount > 0,
      error: error,
    );
  }

  void resetCashTransfer() {
    final configuration = state.configuration;

    final availablePoints = state.availablePoints;

    state = WalletTransactionState(
      configuration: configuration,
      availablePoints: availablePoints,
    );

    initReference();
  }

  Future<void> processUserWithdrawal({
    required TransactionData transaction,
    required SenderApproval approval,
    required bool isCreditAgent,
  }) async {
    state = state.copyWith(isLoading: true, error: null, loyaltyResult: null);

    final analytics = ref.read(analyticsServiceProvider);

    final parameters = <String, String>{
      'currency': transaction.c,
      'amount': (transaction.a / 100).toString(),
    };

    try {
      analytics.logTransactionStarted(
        transactionType: 'cash_withdrawal',
        transactionData: parameters,
      );

      final service = ref.read(walletApiServiceProvider);

      await performanceService.trace('cash_withdrawal', () async {
        if (isCreditAgent) {
          await service.creditAgentProcessUserWithdrawal(transaction, approval);
        } else {
          await service.processUserWithdrawal(transaction, approval);
        }
      });

      state = state.copyWith(isLoading: false);

      analytics.logTransactionCompleted(
        transactionType: 'cash_withdrawal',
        transactionData: parameters,
      );
    } catch (_) {
      state = state.copyWith(isLoading: false);

      analytics.logTransactionFailed(
        transactionType: 'cash_withdrawal',
        transactionData: parameters,
      );

      rethrow;
    }
  }

  Future<void> merchantVoucherPayment({
    required TransactionData transaction,
    required TransactionData voucher,
  }) async {
    state = state.copyWith(isLoading: true, error: null, loyaltyResult: null);

    final analytics = ref.read(analyticsServiceProvider);

    final parameters = <String, String>{
      'currency': transaction.c,
      'amount': (transaction.a / 100).toString(),
    };

    try {
      analytics.logTransactionStarted(
        transactionType: 'merchant_payment',
        transactionData: parameters,
      );

      final service = ref.read(walletApiServiceProvider);

      await performanceService.trace('merchant_payment', () async {
        await service.merchantVoucherPayment(
          transaction: transaction,
          voucher: voucher,
        );
      });

      state = state.copyWith(isLoading: false);

      analytics.logTransactionCompleted(
        transactionType: 'merchant_payment',
        transactionData: parameters,
      );
    } catch (_) {
      state = state.copyWith(isLoading: false);

      analytics.logTransactionFailed(
        transactionType: 'merchant_payment',
        transactionData: parameters,
      );

      rethrow;
    }
  }

  void updateAmountPay(TransactionData data) {
    _applyMerchantPaymentAmount(data, paymentFeeContribution: false);
  }

  void updatePaymentFeeContribution(
    TransactionData data, {
    required bool paymentFeeContribution,
  }) {
    _applyMerchantPaymentAmount(
      data,
      paymentFeeContribution: paymentFeeContribution,
    );
  }

  void _applyMerchantPaymentAmount(
    TransactionData data, {
    required bool paymentFeeContribution,
  }) {
    final reference = data.r.trim();
    final identifier = data.s.trim();

    /*
     * The merchant-signed QR contract remains unchanged:
     *
     * a = purchase amount in minor units
     * f = calculated payment fee in minor units
     *
     * totalDebit exists only in Flutter state and depends
     * on the payer's contribution choice.
     */
    final amount = data.a / 100;

    final configuredPaymentFee = data.f / 100;

    final appliedPaymentFee = paymentFeeContribution
        ? configuredPaymentFee
        : 0.0;

    final totalDebit = amount + appliedPaymentFee;

    final remaining = state.balance - totalDebit;

    final insufficient = totalDebit > state.balance;

    String? error;

    if (insufficient) {
      error = paymentFeeContribution
          ? 'Insufficient balance including support contribution'
          : 'Insufficient balance';
    }

    state = state.copyWith(
      amount: amount,
      identifier: identifier,
      grossAmount: totalDebit,
      feeAmount: appliedPaymentFee,
      taxAmount: 0,
      totalDebit: totalDebit,
      paymentFeeContribution: paymentFeeContribution,
      isValid:
          amount > 0 &&
          state.currency != null &&
          reference.isNotEmpty &&
          identifier.isNotEmpty &&
          !insufficient,
      remaining: remaining,
      reference: reference,
      loyaltyResult: null,
      error: error,
    );
  }

  Future<void> merchantPayment({required TransactionData transaction}) async {
    state = state.copyWith(isLoading: true, error: null, loyaltyResult: null);

    final analytics = ref.read(analyticsServiceProvider);

    final parameters = <String, String>{
      'currency': transaction.c,
      'amount': (transaction.a / 100).toString(),
      'payment_fee_contribution': state.paymentFeeContribution.toString(),
    };

    analytics.logTransactionStarted(
      transactionType: 'user_merchant_payment',
      transactionData: parameters,
    );

    try {
      /*
       * The payer approval uses the fee selected by the
       * payer. The original merchant-signed TransactionData
       * is still sent unchanged.
       */
      final signedTransaction = await getSignedTransaction(
        v: 'v4',
        reference: transaction.r,
        identifier: transaction.s,
        amount: transaction.a / 100,
        feeAmount: state.feeAmount,
        currency: transaction.c,
      );

      final service = ref.read(walletApiServiceProvider);

      TransactionLoyaltyResult? loyaltyResult;

      await performanceService.trace('user_merchant_payment', () async {
        loyaltyResult = await service.merchantPayment(
          paymentData: transaction,
          approval: signedTransaction.senderApproval,
          paymentFeeContribution: state.paymentFeeContribution,
        );
      });

      state = state.copyWith(isLoading: false, loyaltyResult: loyaltyResult);

      analytics.logTransactionCompleted(
        transactionType: 'user_merchant_payment',
        transactionData: parameters,
      );
    } catch (_) {
      state = state.copyWith(isLoading: false, loyaltyResult: null);

      analytics.logTransactionFailed(
        transactionType: 'user_merchant_payment',
        transactionData: parameters,
      );

      rethrow;
    }
  }
}
