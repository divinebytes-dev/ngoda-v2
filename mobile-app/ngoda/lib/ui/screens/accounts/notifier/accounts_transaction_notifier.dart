import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ngoda/data_models/currency/currency.dart';

import 'package:ngoda/services/number_format_service.dart';
import 'package:ngoda/ui/screens/accounts/services/accounts_api_service_provider.dart';
import 'package:ngoda/ui/screens/accounts/state/accounts_transaction_state.dart';

class AccountsTransactionNotifier extends Notifier<AccountsTransactionState> {
  @override
  AccountsTransactionState build() {
    return const AccountsTransactionState();
  }

  Future<void> fundTreasury({
    required double amount,
    required String currency,
  }) async {
    await _runTransaction(() async {
      final service = ref.read(accountsApiServiceProvider);

      await service.fundTreasury(amount: amount, currency: currency);
    });
  }

  Future<void> createPaymentBatch({
    required DateTime startDate,
    required DateTime endDate,
    required String currency,
  }) async {
    await _runTransaction(() async {
      final service = ref.read(accountsApiServiceProvider);

      await service.createPaymentBatch(
        startDate: startDate,
        endDate: endDate,
        currency: currency,
      );
    });
  }

  Future<void> settleCommissionPaymentBatch({required String batchId}) async {
    await _runTransaction(() async {
      final service = ref.read(accountsApiServiceProvider);

      await service.settleCommissionPaymentBatch(batchId: batchId);
    });
  }

  Future<void> settleTaxPaymentBatch({required String batchId}) async {
    await _runTransaction(() async {
      final service = ref.read(accountsApiServiceProvider);

      await service.settleTaxPaymentBatch(batchId: batchId);
    });
  }

  Future<void> appoveTokenAdjustment({
    required String id,
    required String status,
  }) async {
    await _runTransaction(() async {
      final service = ref.read(accountsApiServiceProvider);

      await service.appoveTokenAdjustment(id: id, status: status);
    });
  }

  Future<void> createTaxPaymentBatch({
    required DateTime startDate,
    required DateTime endDate,
    required String currency,
  }) async {
    await _runTransaction(() async {
      final service = ref.read(accountsApiServiceProvider);

      await service.createGovermentTaxPaymentBatch(
        startDate: startDate,
        endDate: endDate,
        currency: currency,
      );
    });
  }

  void initBalance(double balance, Currency? currency) {
    state = state.copyWith(balance: balance, currency: currency);
  }

  void updateStartDate(DateTime value) {
    state = state.copyWith(startDate: value, isValid: state.endDate != null);
  }

  void updateEndDate(DateTime value) {
    state = state.copyWith(endDate: value, isValid: state.startDate != null);
  }

  void updateAmount(String value, double balance) {
    final amount = NumberFormatService.anyToDouble(value);

    if (amount <= 0) {
      state = state.copyWith(
        amount: 0,
        totalDebit: 0,
        remaining: balance,
        balance: balance,
        isValid: false,
      );

      return;
    }

    final remaining = balance - amount;
    final insufficient = amount > balance;

    state = state.copyWith(
      amount: amount,
      balance: balance,
      remaining: remaining,
      totalDebit: amount,
      isValid: !insufficient && state.currency != null,
      error: insufficient ? 'Insufficient balance' : null,
    );
  }

  void updateCurrency(Currency value, Map<String, double> balance) {
    state = state.copyWith(
      currency: value,
      balance: balance[value.code],
      isValid: state.startDate != null && state.endDate != null,
    );
  }

  void updateAmountTreasury(String value, double balance) {
    final amount = NumberFormatService.anyToDouble(value);

    if (amount <= 0) {
      state = state.copyWith(
        amount: 0,
        totalDebit: 0,
        remaining: balance,
        isValid: false,
      );

      return;
    }

    final remaining = balance - amount;
    final insufficient = amount > balance;

    state = state.copyWith(
      amount: amount,
      balance: balance,
      totalDebit: amount,
      isValid: !insufficient && amount > 0,
      remaining: remaining,
      error: insufficient ? 'Insufficient balance' : null,
    );
  }

  void reset() {
    state = const AccountsTransactionState();
  }

  Future<void> _runTransaction(Future<void> Function() action) async {
    state = state.copyWith(isLoading: true);

    try {
      await action();
    } finally {
      state = state.copyWith(isLoading: false);
    }
  }
}
