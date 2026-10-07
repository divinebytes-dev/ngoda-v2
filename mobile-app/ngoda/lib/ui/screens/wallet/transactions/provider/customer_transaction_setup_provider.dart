import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ngoda/data_models/payment/customer_transaction_setup.dart';
import 'package:ngoda/ui/functions/get_current_user.dart';
import 'package:ngoda/ui/screens/agent/providers/agent_dashboard_provider.dart';
import 'package:ngoda/ui/screens/customer/provider/customer_dashboard_provider.dart';
import 'package:ngoda/ui/screens/vendor/provider/vendor_dashboard_provider.dart';

final customerTransactionSetupProvider =
    Provider<AsyncValue<CustomerTransactionSetup>>((ref) {
      final user = getCurrentUser();
      print("role ${user.role} user $user");
      switch (user.role) {
        case 'agent':
          final dashboardAsync = ref.watch(agentDashboardProvider);

          return dashboardAsync.whenData((response) {
            final result = response.result;

            if (result == null) {
              throw StateError('AGENT_DASHBOARD_NOT_FOUND');
            }

            return CustomerTransactionSetup(
              currencyRegistry: result.currencyRegistry,
              loanSummary: result.loanSummary,
              balances: result.customerWallet.currencies.map(
                (key, value) => MapEntry(key, value.balance),
              ),
            );
          });

        case 'vendor':
          print("fetch vendor");
          final dashboardAsync = ref.watch(vendorDashboardProvider);

          return dashboardAsync.whenData((response) {
            final result = response.result;

            if (result == null) {
              throw StateError('VENDOR_DASHBOARD_NOT_FOUND');
            }

            return CustomerTransactionSetup(
              currencyRegistry: result.currencyRegistry,
              loanSummary: result.loanSummary,
              balances: result.customerWallet.currencies.map(
                (key, value) => MapEntry(key, value.balance),
              ),
            );
          });

        default:
          final dashboardAsync = ref.watch(customerDashboardProvider);
          print("fetch customer");
          return dashboardAsync.whenData((response) {
            final result = response.result;

            if (result == null) {
              throw StateError('CUSTOMER_DASHBOARD_NOT_FOUND');
            }

            return CustomerTransactionSetup(
              currencyRegistry: result.currencyRegistry,
              loanSummary: result.loanSummary,
              balances: result.wallet.currencies.map(
                (key, value) => MapEntry(key, value.balance),
              ),
            );
          });
      }
    });
