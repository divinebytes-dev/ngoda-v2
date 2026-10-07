import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ngoda/data_models/currency/currency.dart';
import 'package:ngoda/data_models/fee/fee_config.dart';
import 'package:ngoda/services/number_format_service.dart';
import 'package:ngoda/ui/enums/enums.dart';
import 'package:ngoda/ui/functions/get_transaction_edge_function.dart';
import 'package:ngoda/ui/functions/identifier_validation.dart';
import 'package:ngoda/ui/screens/finance/services/finance_api_service_provider.dart';
import 'package:ngoda/ui/screens/finance/state/finance_transaction_state.dart';
import 'package:uuid/uuid.dart';

class FinanceTransactionNotifier extends Notifier<FinanceTransactionState> {
  @override
  FinanceTransactionState build() {
    return const FinanceTransactionState();
  }

  void initReference() {
    state = state.copyWith(reference: const Uuid().v4());
  }

  void setType(FinanceTransactionType type) {
    state = state.copyWith(type: type);
  }

  void initBalance(double balance, Currency? currency) {
    state = state.copyWith(
      balance: balance,
      remaining: balance,
      currency: currency,
      isValid: false,
    );
  }

  void setValid(bool value) {
    state = state.copyWith(isValid: value);
  }

  Future<void> externalFunding({
    required double amount,
    required String currency,
  }) async {
    state = state.copyWith(isLoading: true);

    try {
      final service = ref.read(financeApiServiceProvider);

      await service.externalFunding(amount: amount, currency: currency);

      state = state.copyWith(isLoading: false);
    } catch (_) {
      state = state.copyWith(isLoading: false);

      rethrow;
    }
  }

  Future<void> customerDirectDeposit() async {
    state = state.copyWith(isLoading: true);

    try {
      final service = ref.read(financeApiServiceProvider);

      await service.customerDirectDeposit(
        email: state.email,
        amount: state.totalDebit,
        currency: state.currency!.code,
        reference: state.reference!,
      );

      state = state.copyWith(isLoading: false);
    } catch (_) {
      state = state.copyWith(isLoading: false);

      rethrow;
    }
  }

  Future<void> reverseDocument({
    required String docNo,
    required String transactionType,
  }) async {
    state = state.copyWith(isLoading: true);

    try {
      final service = ref.read(financeApiServiceProvider);

      final edgeFunction = getTransactionEdgeFunction(transactionType);

      await service.reverseDocument(
        docNo: docNo,
        transactionType: transactionType,
        edgeFunction: edgeFunction,
      );

      state = state.copyWith(isLoading: false);
    } catch (_) {
      state = state.copyWith(isLoading: false);

      rethrow;
    }
  }

  Future<void> reconcilManualReviewLiquidationJob({
    required String jobId,
    required String txHash,
  }) async {
    state = state.copyWith(isLoading: true);

    try {
      final service = ref.read(financeApiServiceProvider);

      await service.reconcilManualReviewLiquidationJob(
        jobId: jobId,
        txHash: txHash,
      );

      state = state.copyWith(isLoading: false);
    } catch (_) {
      state = state.copyWith(isLoading: false);

      rethrow;
    }
  }

  Future<void> goldPurchase() async {
    state = state.copyWith(isLoading: true);

    try {
      final service = ref.read(financeApiServiceProvider);

      await service.goldPurchase(
        grams: state.grams,
        currency: state.currency!.code,
        price: state.price,
        serial: state.serialNumber,
      );

      state = state.copyWith(isLoading: false);
    } catch (_) {
      state = state.copyWith(isLoading: false);

      rethrow;
    }
  }

  Future<void> taxPaymentBatchApproval({
    required String batchId,
    required String action,
  }) async {
    state = state.copyWith(isLoading: true);

    try {
      final service = ref.read(financeApiServiceProvider);

      await service.taxPaymentBatchApproval(batchId: batchId, action: action);

      state = state.copyWith(isLoading: false);
    } catch (_) {
      state = state.copyWith(isLoading: false);

      rethrow;
    }
  }

  Future<void> commissionPaymentBatchApproval({
    required String batchId,
    required String action,
  }) async {
    state = state.copyWith(isLoading: true);

    try {
      final service = ref.read(financeApiServiceProvider);

      await service.commissionPaymentBatchApproval(
        batchId: batchId,
        action: action,
      );

      state = state.copyWith(isLoading: false);
    } catch (_) {
      state = state.copyWith(isLoading: false);

      rethrow;
    }
  }

  void updateAmount(String value, double balance) {
    final amount = NumberFormatService.anyToDouble(value);

    if (amount <= 0) {
      state = state.copyWith(
        amount: 0,
        balance: balance,
        remaining: balance,
        totalDebit: 0,
        price: 0,
        isValid: false,
      );

      return;
    }

    final remaining = balance - amount;
    final insufficient = amount > balance;
    final emailValid = isValidEmail(state.email);

    final errors = <String>[];

    if (!emailValid) {
      errors.add('Invalid email');
    }

    if (insufficient) {
      errors.add('Insufficient balance');
    }

    state = state.copyWith(
      amount: amount,
      balance: balance,
      remaining: remaining,
      totalDebit: amount,
      price: amount,
      isValid: !insufficient && emailValid,
      error: errors.isEmpty ? null : errors.join('\n'),
    );
  }

  void updateDirectDepositAmount(
    String value,
    double balance, {
    FeeConfig? feeConfig,
  }) {
    final amount = NumberFormatService.anyToDouble(value);

    if (amount <= 0) {
      state = state.copyWith(
        amount: 0,
        balance: balance,
        remaining: balance,
        totalDebit: 0,
        feeAmount: 0,
        feePercent: feeConfig?.percentage ?? 0,
        isValid: false,
      );

      return;
    }

    final feeAmount = feeConfig?.calculateFee(amount) ?? 0;

    final remaining = balance - amount;
    final insufficient = amount > balance;
    final emailValid = isValidEmail(state.email);

    final errors = <String>[];

    if (!emailValid) {
      errors.add('Invalid email');
    }

    if (insufficient) {
      errors.add('Insufficient balance');
    }

    state = state.copyWith(
      amount: amount - feeAmount,
      balance: balance,
      remaining: remaining,
      totalDebit: amount,
      price: amount,
      isValid: !insufficient && emailValid,
      feeAmount: NumberFormatService.anyToDouble(feeAmount),
      feePercent: feeConfig?.percentage ?? 0,
      error: errors.isEmpty ? null : errors.join('\n'),
    );
  }

  void updateAmountExt(String value) {
    final amount = NumberFormatService.anyToDouble(value);

    state = state.copyWith(
      amount: amount > 0 ? amount : 0,
      isValid: amount > 0,
    );
  }

  void updateCurrency(Currency value, Map<String, double> balance) {
    final currentBalance = balance[value.code] ?? 0;

    state = state.copyWith(
      currency: value,
      balance: currentBalance,
      remaining: currentBalance,
      amount: 0,
      totalDebit: 0,
      feeAmount: 0,
      isValid: false,
    );
  }

  void updateEmail(String value) {
    final emailValid = isValidEmail(value);

    final insufficient = state.totalDebit > state.balance;

    final errors = <String>[];

    if (!emailValid) {
      errors.add('Invalid email');
    }

    if (insufficient) {
      errors.add('Insufficient balance');
    }

    state = state.copyWith(
      email: value,
      isValid: !insufficient && emailValid && state.amount > 0,
      error: errors.isEmpty ? null : errors.join('\n'),
    );
  }

  void updateGoldQty(String value) {
    final grams = NumberFormatService.anyToDouble(value);

    final totalDebit = grams * state.price;
    final remaining = state.balance - totalDebit;
    final insufficient = totalDebit > state.balance;

    state = state.copyWith(
      grams: grams,
      totalDebit: totalDebit,
      remaining: remaining,
      isValid:
          grams > 0 &&
          state.price > 0 &&
          !insufficient &&
          state.serialNumber.isNotEmpty,
      error: insufficient ? 'Insufficient balance' : null,
    );
  }

  void updateGoldPrice(String value) {
    final price = NumberFormatService.anyToDouble(value);

    final totalDebit = state.grams * price;

    final remaining = state.balance - totalDebit;

    final insufficient = totalDebit > state.balance;

    state = state.copyWith(
      price: price,
      totalDebit: totalDebit,
      remaining: remaining,
      isValid:
          state.grams > 0 &&
          price > 0 &&
          !insufficient &&
          state.serialNumber.isNotEmpty,
      error: insufficient ? 'Insufficient balance' : null,
    );
  }

  void updateGoldSerial(String serial) {
    final insufficient = state.totalDebit > state.balance;

    state = state.copyWith(
      serialNumber: serial,
      isValid:
          state.grams > 0 &&
          !insufficient &&
          state.price > 0 &&
          serial.isNotEmpty,
      error: insufficient ? 'Insufficient balance' : null,
    );
  }

  void reset() {
    state = const FinanceTransactionState();

    initReference();
  }
}
