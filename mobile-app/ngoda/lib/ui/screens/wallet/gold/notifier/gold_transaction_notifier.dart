import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';
import 'package:ngoda/core/providers/analytics_service_provider.dart';
import 'package:ngoda/data_models/fee/fee_config.dart';
import 'package:ngoda/data_models/gamification/loyalty/transaction_loyalty_result.dart';
import 'package:ngoda/services/calculation_service.dart';
import 'package:ngoda/services/performance_service.dart';
import 'package:ngoda/ui/enums/enums.dart';
import 'package:ngoda/ui/functions/get_current_user.dart';
import 'package:ngoda/ui/functions/get_signed_transaction.dart';
import 'package:ngoda/ui/functions/identifier_validation.dart';
import 'package:ngoda/ui/screens/wallet/gold/service/gold_api_service_provider.dart';
import 'package:ngoda/ui/screens/wallet/gold/state/gold_transaction_state.dart';
import 'package:uuid/uuid.dart';

class GoldTransactionNotifier extends Notifier<GoldTransactionState> {
  final Logger logger = Logger('GoldTransactionNotifier');

  final PerformanceService performanceService = PerformanceService();

  @override
  GoldTransactionState build() {
    return const GoldTransactionState();
  }

  void initReference() {
    final reference = const Uuid().v4();

    state = state.copyWith(
      reference: reference,
      error: null,
      loyaltyResult: null,
    );

    logger.info('new reference : $reference');
  }

  void setPrice(double price, double spreadRate) {
    logger.info(
      'gold price $price '
      'spreadRate $spreadRate',
    );

    state = state.copyWith(
      goldPrice: price,
      spreadRate: spreadRate,
      error: null,
    );

    _recalculate();
  }

  void setConfig({
    required double goldPrice,
    required double feeRate,
    required double spreadRate,
  }) {
    state = state.copyWith(
      goldPrice: goldPrice,
      feeRate: feeRate,
      spreadRate: spreadRate,
      error: null,
    );

    _recalculate();
  }

  void updateBalance(double value) {
    final balance = value.isFinite && value >= 0 ? value : 0.0;

    state = state.copyWith(balance: balance, error: null);

    _recalculate();
  }

  void updateEmail(String email) {
    final value = email.trim();

    state = state.copyWith(email: value, error: null);

    _recalculate();
  }

  void updateAmount(
    String value, {
    required double balance,
    FeeConfig? feeConfig,
    required String currency,
  }) {
    final cleaned = value.replaceAll(',', '').trim();

    final parsed = double.tryParse(cleaned) ?? 0;

    final amount = parsed.isFinite && parsed > 0 ? parsed : 0.0;

    final availableBalance = balance.isFinite && balance >= 0 ? balance : 0.0;

    state = state.copyWith(
      amount: amount,
      balance: availableBalance,
      feeRate: feeConfig?.percentage ?? 0,
      currency: currency,
      result: null,
      loyaltyResult: null,
      error: null,
    );

    _recalculate();
  }

  void updateCurrency(String currency) {
    state = state.copyWith(currency: currency, result: null, error: null);

    _recalculate();
  }

  void updateTransactionType(GoldTransactionType type) {
    state = state.copyWith(transactionType: type, result: null, error: null);

    _recalculate();
  }

  void toggleInputMode(InputMode mode) {
    state = state.copyWith(inputMode: mode, result: null, error: null);

    _recalculate();
  }

  void _recalculate() {
    final amount = state.amount;

    /*
   * A usable amount is required for every gold transaction.
   */
    if (amount <= 0 || !amount.isFinite) {
      state = state.copyWith(
        result: null,
        totalDebit: 0,
        remaining: state.balance,
        isValid: false,
        error: null,
      );

      return;
    }

    /*
   * Gold Buy and Gold Sell require the current market price.
   *
   * Gold Transfer does not require a market price because the
   * transaction is denominated directly in gold.
   */
    final requiresGoldPrice =
        state.transactionType != GoldTransactionType.transfer;

    if (requiresGoldPrice &&
        (state.goldPrice <= 0 || !state.goldPrice.isFinite)) {
      state = state.copyWith(
        result: null,
        totalDebit: 0,
        remaining: state.balance,
        isValid: false,
        error: null,
      );

      return;
    }

    /*
   * Gold pricing/calculation remains owned by CalculationService.
   */
    final result = CalculationService.calculateGoldTransaction(
      principal: amount,
      currency: state.currency,
      transactionType: state.transactionType,
      goldMarketPrice: state.goldPrice,
      spreadRate: state.spreadRate,
      feeRate: state.feeRate,
    );

    final totalDebit = result.fiatPaid;

    final isBuy = state.transactionType == GoldTransactionType.buy;

    final requiredBalance = isBuy ? totalDebit : result.quantity;

    final remaining = state.balance - requiredBalance;

    final insufficient = requiredBalance > state.balance;

    /*
   * Recipient validation belongs only to Gold Transfer.
   */
    final requiresRecipient =
        state.transactionType == GoldTransactionType.transfer;

    final emailValid = !requiresRecipient || isValidEmail(state.email.trim());

    String? error;

    if (requiresRecipient && !emailValid) {
      error = 'Invalid email';
    }

    logger.info(
      'state balance = ${state.balance} '
      'amount = $amount '
      'quantity = ${result.quantity} '
      'insufficient = $insufficient '
      'goldPrice = ${state.goldPrice}',
    );

    state = state.copyWith(
      result: result,
      totalDebit: totalDebit,
      remaining: remaining,
      isValid: !insufficient && emailValid && amount > 0,
      error: error,
    );
  }
  // void _recalculate() {
  //   final amount = state.amount;

  //   /*
  //    * Do not call the Gold calculation
  //    * service until there is a usable
  //    * amount and price.
  //    *
  //    * This also clears a calculation
  //    * left by a previous amount.
  //    */
  //   if (amount <= 0 ||
  //       !amount.isFinite ||
  //       state.goldPrice <= 0 ||
  //       !state.goldPrice.isFinite) {
  //     state = state.copyWith(
  //       result: null,
  //       totalDebit: 0,
  //       remaining: state.balance,
  //       isValid: false,
  //       error: null,
  //     );

  //     return;
  //   }

  //   /*
  //    * Gold pricing remains owned by
  //    * CalculationService.
  //    *
  //    * Do not reproduce or alter the
  //    * backend-aligned pricing formula
  //    * in this notifier.
  //    */
  //   final result = CalculationService.calculateGoldTransaction(
  //     principal: amount,
  //     currency: state.currency,
  //     transactionType: state.transactionType,
  //     goldMarketPrice: state.goldPrice,
  //     spreadRate: state.spreadRate,
  //     feeRate: state.feeRate,
  //   );

  //   final totalDebit = result.fiatPaid;

  //   final isBuy = state.transactionType == GoldTransactionType.buy;

  //   final requiredBalance = isBuy ? totalDebit : result.quantity;

  //   final remaining = state.balance - requiredBalance;

  //   final insufficient = requiredBalance > state.balance;

  //   /*
  //    * Recipient validation belongs only
  //    * to Gold Transfer.
  //    *
  //    * Buy and Sell must not become
  //    * invalid simply because there is
  //    * no recipient email.
  //    */
  //   final requiresRecipient =
  //       state.transactionType == GoldTransactionType.transfer;

  //   final emailValid = !requiresRecipient || isValidEmail(state.email.trim());

  //   String? error;

  //   if (requiresRecipient && !emailValid) {
  //     error = 'Invalid email';
  //   }

  //   logger.info(
  //     'state balance = ${state.balance} '
  //     'amount = $amount '
  //     'quantity = ${result.quantity} '
  //     'insufficient = $insufficient '
  //     'goldPrice = ${state.goldPrice}',
  //   );

  //   state = state.copyWith(
  //     result: result,
  //     totalDebit: totalDebit,
  //     remaining: remaining,
  //     isValid: !insufficient && emailValid && amount > 0,
  //     error: error,
  //   );
  // }

  Future<void> initBuy() async {
    _initializeTransaction(GoldTransactionType.buy);
  }

  Future<void> initTransfer() async {
    _initializeTransaction(GoldTransactionType.transfer);
  }

  Future<void> initSell() async {
    _initializeTransaction(GoldTransactionType.sell);
  }

  void _initializeTransaction(GoldTransactionType type) {
    /*
     * Every new Gold flow gets a clean
     * state and one transaction
     * reference.
     */
    state = GoldTransactionState(
      transactionType: type,
      reference: const Uuid().v4(),
    );

    logger.info(
      'new reference : '
      '${state.reference}',
    );
  }

  Future<void> goldBuy() async {
    final reference = _requiredReference();

    if (!state.isValid || state.amount <= 0) {
      throw StateError('Invalid gold buy transaction.');
    }

    state = state.copyWith(isLoading: true, error: null, loyaltyResult: null);

    final analytics = ref.read(analyticsServiceProvider);

    final parameters = <String, String>{
      'currency': state.currency,
      'amount': state.amount.toString(),
    };

    try {
      final user = getCurrentUser();

      final userId = user.userId;

      if (userId == null || userId.trim().isEmpty) {
        throw StateError('User ID is required.');
      }

      final signedTransaction = await getSignedTransaction(
        v: 'v7',
        reference: reference,
        identifier: userId,
        amount: state.amount,
        currency: state.currency,
      );

      analytics.logTransactionStarted(
        transactionType: 'gold_buy',
        transactionData: parameters,
      );

      final service = ref.read(goldApiServiceProvider);

      TransactionLoyaltyResult? loyaltyResult;

      await performanceService.trace('gold_buy', () async {
        loyaltyResult = await service.goldBuy(
          transactionData: signedTransaction.transactionData,
        );
      });

      analytics.logTransactionCompleted(
        transactionType: 'gold_buy',
        transactionData: parameters,
      );

      state = state.copyWith(
        isLoading: false,
        loyaltyResult: loyaltyResult,
        error: null,
      );
    } catch (error) {
      state = state.copyWith(isLoading: false, error: error.toString());

      analytics.logTransactionFailed(
        transactionType: 'gold_buy',
        transactionData: parameters,
      );

      rethrow;
    }
  }

  Future<void> goldSell() async {
    final reference = _requiredReference();

    if (!state.isValid || state.amount <= 0) {
      throw StateError('Invalid gold sell transaction.');
    }

    state = state.copyWith(isLoading: true, error: null, loyaltyResult: null);

    final analytics = ref.read(analyticsServiceProvider);

    final parameters = <String, String>{
      'currency': state.currency,
      'amount': state.amount.toString(),
    };

    try {
      final user = getCurrentUser();

      final userId = user.userId;

      if (userId == null || userId.trim().isEmpty) {
        throw StateError('User ID is required.');
      }

      analytics.logTransactionStarted(
        transactionType: 'gold_sell',
        transactionData: parameters,
      );

      final signedTransaction = await getSignedTransaction(
        v: 'v7',
        reference: reference,
        identifier: userId,
        amount: state.amount,
        currency: state.currency,
      );

      final service = ref.read(goldApiServiceProvider);

      await performanceService.trace('gold_sell', () async {
        await service.goldSell(
          transactionData: signedTransaction.transactionData,
        );
      });

      analytics.logTransactionCompleted(
        transactionType: 'gold_sell',
        transactionData: parameters,
      );

      state = state.copyWith(isLoading: false, error: null);
    } catch (error) {
      state = state.copyWith(isLoading: false, error: error.toString());

      analytics.logTransactionFailed(
        transactionType: 'gold_sell',
        transactionData: parameters,
      );

      rethrow;
    }
  }

  Future<void> goldTransfer() async {
    final reference = _requiredReference();

    if (!state.isValid ||
        state.amount <= 0 ||
        !isValidEmail(state.email.trim())) {
      throw StateError('Invalid gold transfer transaction.');
    }

    state = state.copyWith(isLoading: true, error: null, loyaltyResult: null);

    final analytics = ref.read(analyticsServiceProvider);

    final parameters = <String, String>{
      'currency': state.currency,
      'amount': state.amount.toString(),
    };

    try {
      analytics.logTransactionStarted(
        transactionType: 'gold_transfer',
        transactionData: parameters,
      );

      final signedTransaction = await getSignedTransaction(
        v: 'v6',
        reference: reference,
        identifier: state.email.trim(),
        amount: state.amount,
        currency: state.currency,
      );

      final service = ref.read(goldApiServiceProvider);

      await performanceService.trace('gold_transfer', () async {
        await service.goldTransfer(
          transactionData: signedTransaction.transactionData,
        );
      });

      analytics.logTransactionCompleted(
        transactionType: 'gold_transfer',
        transactionData: parameters,
      );

      state = state.copyWith(isLoading: false, error: null);
    } catch (error) {
      state = state.copyWith(isLoading: false, error: error.toString());

      analytics.logTransactionFailed(
        transactionType: 'gold_transfer',
        transactionData: parameters,
      );

      rethrow;
    }
  }

  String _requiredReference() {
    final reference = state.reference?.trim();

    if (reference == null || reference.isEmpty) {
      throw StateError('Transaction reference is required.');
    }

    return reference;
  }

  void reset() {
    state = const GoldTransactionState();
  }
}
