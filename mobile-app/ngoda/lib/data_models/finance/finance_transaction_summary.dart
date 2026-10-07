import 'package:ngoda/data_models/finance/finance_currency_transactions.dart';
import 'package:ngoda/data_models/finance/finance_transaction.dart';

class FinanceTransactionSummary {
  FinanceTransactionSummary({
    required Map<String, FinanceCurrencyTransactions> currencies,
  }) : currencies = Map.unmodifiable(currencies);

  final Map<String, FinanceCurrencyTransactions> currencies;

  factory FinanceTransactionSummary.fromJson(Map<String, dynamic> json) {
    final result = <String, FinanceCurrencyTransactions>{};

    for (final entry in json.entries) {
      if (entry.value is! Map) {
        continue;
      }

      final currency = entry.key.trim().toLowerCase();

      if (currency.isEmpty) {
        continue;
      }

      result[currency] = FinanceCurrencyTransactions.fromJson(
        Map<String, dynamic>.from(entry.value as Map),
      );
    }

    return FinanceTransactionSummary(currencies: result);
  }

  FinanceCurrencyTransactions? getByCurrency(String currency) {
    return currencies[currency.trim().toLowerCase()];
  }

  FinanceCurrencyTransactions? operator [](String currency) {
    return getByCurrency(currency);
  }

  List<FinanceTransaction> byCurrency(String currency) {
    return getByCurrency(currency)?.transactions ?? const [];
  }

  List<String> get currencyList {
    return List.unmodifiable(currencies.keys);
  }

  List<String> get sortedCurrencyList {
    final result = [...currencies.keys]..sort();

    return List.unmodifiable(result);
  }

  FinanceTransactionSummary replaceCurrency({
    required String currency,
    required FinanceCurrencyTransactions statement,
  }) {
    final normalized = currency.trim().toLowerCase();

    return FinanceTransactionSummary(
      currencies: {...currencies, normalized: statement},
    );
  }

  bool get isEmpty => currencies.isEmpty;

  bool get isNotEmpty => currencies.isNotEmpty;
}
