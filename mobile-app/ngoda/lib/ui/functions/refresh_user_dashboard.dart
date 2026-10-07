import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ngoda/ui/functions/get_current_user.dart';
import 'package:ngoda/ui/screens/accounts/providers/accounts_dashboard_provider.dart';
import 'package:ngoda/ui/screens/customer/provider/customer_dashboard_provider.dart';
import 'package:ngoda/ui/screens/finance/providers/finance_dashboard_provider.dart';
import 'package:ngoda/ui/screens/vendor/provider/vendor_dashboard_provider.dart';

// Import the existing file that defines:
// complianceDashboardProvider

void refreshUserDashboard(WidgetRef ref) {
  final role = getCurrentUser().role?.trim().toLowerCase();

  switch (role) {
    case 'accounts':
      ref.invalidate(accountsDashboardProvider);

    //   case 'agent':
    //     ref.invalidate(agentDashboardProvider);

    case 'customer':
      ref.invalidate(customerDashboardProvider);

    case 'finance':
      ref.invalidate(financeDashboardProvider);

    //   case 'merchant':
    //     ref.invalidate(merchantDashboardProvider);

    //   case 'treasury':
    //     ref.invalidate(treasuryDashboardProvider);

    case 'vendor':
      ref.invalidate(vendorDashboardProvider);

    //   case 'compliance':
    //     ref.invalidate(complianceDashboardProvider);

    // default:
    // return;
  }
}
