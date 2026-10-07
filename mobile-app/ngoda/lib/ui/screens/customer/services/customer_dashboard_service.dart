import 'package:logging/logging.dart';

import 'package:ngoda/data_models/core/result.dart';
import 'package:ngoda/data_models/currency/currency.dart';
import 'package:ngoda/data_models/currency/currency_registry.dart';
import 'package:ngoda/data_models/customer/customer_dashboard.dart';
import 'package:ngoda/services/currency_service.dart';
import 'package:ngoda/ui/screens/wallet/loan/service/loan_api_service.dart';
import 'package:ngoda/ui/screens/customer/services/customer_api_service.dart';

class CustomerDashboardService {
  final CustomerApiService customerApiService;
  final LoanApiService loanApiService;

  CustomerDashboardService(this.customerApiService, this.loanApiService);

  final logger = Logger('CustomerDashboardService');

  Future<R<CustomerDashboard>> load() async {
    try {
      final response = await customerApiService.getDashboard();

      final currencies = (response['currencies'] as List)
          .map((e) => Currency.fromJson(e as Map<String, dynamic>))
          .toList();

      /*
       * CurrencyService is the application-level currency
       * lookup used by services such as NumberFormatService.
       *
       * Each dashboard receives its supported currencies
       * from the backend, so loading the dashboard refreshes
       * the currency lookup for the current user/context.
       */
      CurrencyService.initialize(currencies);

      /*
       * CurrencyRegistry belongs to the dashboard/domain
       * model and provides currency lookup within the
       * dashboard data itself.
       */
      final registry = CurrencyRegistry.fromCurrencies(currencies);

      final dashboard = CustomerDashboard.fromJson(
        walletJson: response['wallet'],
        loanSummary: response['loan'],
        currencies: currencies,
        currencyRegistry: registry,
        loyaltyJson: response['loyalty'],
      );

      return R(result: dashboard);
    } catch (e) {
      logger.warning('Failed to load customer dashboard: $e');

      return R(error: e.toString());
    }
  }
}
