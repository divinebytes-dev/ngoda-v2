import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ngoda/data_models/currency/currency.dart';
import 'package:ngoda/services/number_format_service.dart';
import 'package:ngoda/ui/functions/identifier_validation.dart';
import 'package:ngoda/ui/screens/treasury/service/treasury_api_service_provider.dart';
import 'package:ngoda/ui/screens/treasury/state/treasury_transaction_state.dart';
import 'package:uuid/uuid.dart';

class TreasuryTransactionNotifier extends Notifier<TreasuryTransactionState> {
  @override
  TreasuryTransactionState build() {
    return const TreasuryTransactionState();
  }

  void initReference() {
    final reference = const Uuid().v4();

    state = state.copyWith(reference: reference);
  }

  void updateCurrency(Currency value, Map<String, double> balance) {
    final emailValid = isValidEmail(state.email);

    String? error;

    if (!emailValid) {
      error = 'Invalid email';
    }

    final currentBalance = balance[value.code] ?? 0.0;

    final insufficient = state.amount > currentBalance;

    if (insufficient) {
      if (error == null) {
        error = 'Insufficient balance';
      } else {
        error = '$error\nInsufficient balance';
      }
    }

    state = state.copyWith(
      currency: value,
      balance: currentBalance,
      remaining: currentBalance - state.amount,
      totalDebit: state.amount,
      error: error,
      isValid: emailValid && state.amount > 0 && !insufficient,
    );
  }

  void updateCreditAgentEmail(String value) {
    final emailValid = isValidEmail(value);

    String? error;

    if (!emailValid) {
      error = 'Invalid email';
    }

    state = state.copyWith(email: value, error: error, isValid: emailValid);
  }

  void updateEmail(String value) {
    final emailValid = isValidEmail(value);
    final insufficient = state.totalDebit > state.balance;

    String? error;

    if (!emailValid) {
      error = 'Invalid email';
    }

    if (insufficient) {
      if (error == null) {
        error = 'Insufficient balance';
      } else {
        error = '$error\nInsufficient balance';
      }
    }

    state = state.copyWith(
      email: value,
      error: error,
      isValid: emailValid && state.amount > 0 && !insufficient,
    );
  }

  void updateAmount(String value, double balance) {
    final amount = NumberFormatService.anyToDouble(value);

    if (amount <= 0) {
      state = state.copyWith(
        amount: 0,
        balance: balance,
        remaining: balance,
        totalDebit: 0,
        isValid: false,
      );
      return;
    }

    final remaining = balance - amount;
    final insufficient = amount > balance;
    final emailValid = isValidEmail(state.email);

    String? error;

    if (!emailValid) {
      error = 'Invalid email';
    }

    if (insufficient) {
      if (error == null) {
        error = 'Insufficient balance';
      } else {
        error = '$error\nInsufficient balance';
      }
    }

    state = state.copyWith(
      amount: amount,
      balance: balance,
      remaining: remaining,
      totalDebit: amount,
      isValid: !insufficient && emailValid,
      error: error,
    );
  }

  Future<void> executeTokenAdjustment({
    required String id,
    required String blockchainCode,
  }) async {
    state = state.copyWith(isLoading: true);

    try {
      final service = ref.read(treasuryApiServiceProvider);

      await service.executeTokenAdjustment(
        id: id,
        blockchainCode: blockchainCode,
      );
    } finally {
      state = state.copyWith(isLoading: false);
    }
  }

  Future<void> processIncompleteBlockchainTransaction({
    required String id,
  }) async {
    state = state.copyWith(isLoading: true);

    try {
      final service = ref.read(treasuryApiServiceProvider);

      await service.processIncompleteBlockchainTransaction(id: id);

      state = state.copyWith(isLoading: false);
    } catch (_) {
      state = state.copyWith(isLoading: false);

      rethrow;
    }
  }

  Future<void> fundAgent() async {
    state = state.copyWith(isLoading: true);

    try {
      final service = ref.read(treasuryApiServiceProvider);

      await service.fundAgent(
        email: state.email,
        amount: state.amount,
        currency: state.currency!.code,
        reference: state.reference!,
      );

      state = state.copyWith(isLoading: false);
    } catch (_) {
      state = state.copyWith(isLoading: false);

      rethrow;
    }
  }

  Future<void> fundCreditAgent() async {
    state = state.copyWith(isLoading: true);

    try {
      final service = ref.read(treasuryApiServiceProvider);

      await service.fundCreditAgent(
        email: state.email,
        amount: state.amount,
        currency: state.currency!.code,
        reference: state.reference!,
      );

      state = state.copyWith(isLoading: false);
    } catch (_) {
      state = state.copyWith(isLoading: false);

      rethrow;
    }
  }

  Future<void> approveCreditAgent() async {
    state = state.copyWith(isLoading: true);

    try {
      final service = ref.read(treasuryApiServiceProvider);

      await service.approveCreditAgent(email: state.email);

      state = state.copyWith(isLoading: false);
    } catch (_) {
      state = state.copyWith(isLoading: false);

      rethrow;
    }
  }

  void reset() {
    state = const TreasuryTransactionState();
  }
}
