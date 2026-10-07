import 'package:ngoda/data_models/currency/currency_balance.dart';
import 'package:ngoda/services/number_conversion_service.dart';

class DailyTransactionSummary {
  DailyTransactionSummary({
    required Map<String, CurrencyBalance> deposits,
    required Map<String, CurrencyBalance> withdrawals,
    required Map<String, CurrencyBalance> payments,
    required Map<String, int> depositCount,
    required Map<String, int> withdrawalCount,
    required Map<String, int> paymentCount,
  }) : deposits = Map.unmodifiable(deposits),
       withdrawals = Map.unmodifiable(withdrawals),
       payments = Map.unmodifiable(payments),
       depositCount = Map.unmodifiable(depositCount),
       withdrawalCount = Map.unmodifiable(withdrawalCount),
       paymentCount = Map.unmodifiable(paymentCount);

  final Map<String, CurrencyBalance> deposits;
  final Map<String, CurrencyBalance> withdrawals;
  final Map<String, CurrencyBalance> payments;

  final Map<String, int> depositCount;
  final Map<String, int> withdrawalCount;
  final Map<String, int> paymentCount;

  factory DailyTransactionSummary.fromJson(Map<String, dynamic> json) {
    final rawData = json['data'];

    final data = rawData is Map ? Map<String, dynamic>.from(rawData) : json;

    return DailyTransactionSummary(
      deposits: _mapCurrencies(data['deposits']),
      withdrawals: _mapCurrencies(data['withdrawals']),
      payments: _mapCurrencies(data['payments']),
      depositCount: _mapCounts(data['deposit_count']),
      withdrawalCount: _mapCounts(data['withdrawal_count']),
      paymentCount: _mapCounts(data['payment_count']),
    );
  }

  factory DailyTransactionSummary.empty() {
    return DailyTransactionSummary(
      deposits: const {},
      withdrawals: const {},
      payments: const {},
      depositCount: const {},
      withdrawalCount: const {},
      paymentCount: const {},
    );
  }

  CurrencyBalance? deposit(String currency) {
    return deposits[currency.trim().toLowerCase()];
  }

  CurrencyBalance? withdrawal(String currency) {
    return withdrawals[currency.trim().toLowerCase()];
  }

  CurrencyBalance? payment(String currency) {
    return payments[currency.trim().toLowerCase()];
  }

  int depositTransactions(String currency) {
    return depositCount[currency.trim().toLowerCase()] ?? 0;
  }

  int withdrawalTransactions(String currency) {
    return withdrawalCount[currency.trim().toLowerCase()] ?? 0;
  }

  int paymentTransactions(String currency) {
    return paymentCount[currency.trim().toLowerCase()] ?? 0;
  }

  static Map<String, CurrencyBalance> _mapCurrencies(dynamic value) {
    if (value is! Map) {
      return const {};
    }

    final result = <String, CurrencyBalance>{};

    for (final entry in value.entries) {
      final currency = entry.key.toString().trim().toLowerCase();

      if (currency.isEmpty || entry.value is! Map) {
        continue;
      }

      result[currency] = CurrencyBalance.fromJson(
        Map<String, dynamic>.from(entry.value as Map),
      );
    }

    return result;
  }

  static Map<String, int> _mapCounts(dynamic value) {
    if (value is! Map) {
      return const {};
    }

    final result = <String, int>{};

    for (final entry in value.entries) {
      final currency = entry.key.toString().trim().toLowerCase();

      if (currency.isEmpty) {
        continue;
      }

      result[currency] = NumberConversionService.toInt(entry.value);
    }

    return result;
  }
}

extension DailyTransactionSummaryX on DailyTransactionSummary {
  List<String> get currencyList {
    final currencies = <String>{
      ...deposits.keys,
      ...withdrawals.keys,
      ...payments.keys,
      ...depositCount.keys,
      ...withdrawalCount.keys,
      ...paymentCount.keys,
    };

    return List.unmodifiable(currencies);
  }

  List<String> get sortedCurrencyList {
    final result = [...currencyList]..sort();

    return List.unmodifiable(result);
  }

  double get totalDepositsUsd {
    return deposits.values.fold(
      0.0,
      (total, balance) => total + balance.usdValue,
    );
  }

  double get totalWithdrawalsUsd {
    return withdrawals.values.fold(
      0.0,
      (total, balance) => total + balance.usdValue,
    );
  }

  double get totalPaymentsUsd {
    return payments.values.fold(
      0.0,
      (total, balance) => total + balance.usdValue,
    );
  }

  int get totalDepositCount {
    return depositCount.values.fold(0, (total, count) => total + count);
  }

  int get totalWithdrawalCount {
    return withdrawalCount.values.fold(0, (total, count) => total + count);
  }

  int get totalPaymentCount {
    return paymentCount.values.fold(0, (total, count) => total + count);
  }
}
