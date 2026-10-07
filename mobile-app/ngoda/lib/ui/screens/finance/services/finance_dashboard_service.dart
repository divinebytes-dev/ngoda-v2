import 'package:ngoda/data_models/core/result.dart';
import 'package:ngoda/data_models/currency/currency_registry.dart';
import 'package:ngoda/data_models/finance/finance_dashboard.dart';
import 'package:ngoda/services/currency_service.dart';

import 'package:ngoda/ui/screens/finance/services/finance_api_service.dart';

class FinanceDashboardService {
  const FinanceDashboardService(this._financeApiService);

  final FinanceApiService _financeApiService;

  Future<R<FinanceDashboard>> load() async {
    try {
      final summary = await _financeApiService.getFinanceSummary();

      final registry = CurrencyRegistry.fromCurrencies(summary.currencies);
      CurrencyService.initialize(summary.currencies);

      final dashboard = FinanceDashboard(
        summary: summary,
        currencies: summary.currencies,
        currencyRegistry: registry,
      );

      return R(result: dashboard);
    } catch (error) {
      return R(error: error.toString());
    }
  }
}
