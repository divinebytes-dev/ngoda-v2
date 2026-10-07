import 'package:ngoda/data_models/currency/currency.dart';
import 'package:ngoda/data_models/currency/currency_registry.dart';
import 'package:ngoda/data_models/finance/finance_summary.dart';

class FinanceDashboard {
  FinanceDashboard({
    required this.summary,
    required List<Currency> currencies,
    required this.currencyRegistry,
  }) : currencies = List.unmodifiable(currencies);

  final FinanceSummary summary;

  final List<Currency> currencies;

  final CurrencyRegistry currencyRegistry;

  Currency? currency(String currencyCode) {
    return currencyRegistry.getByCode(currencyCode);
  }

  bool supportsCurrency(String currencyCode) {
    return currencyRegistry.contains(currencyCode);
  }
}
