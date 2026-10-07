import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';

import 'package:ngoda/core/providers/role_error_provider.dart';
import 'package:ngoda/services/dialog_service.dart';
import 'package:ngoda/ui/functions/get_current_user.dart';
import 'package:ngoda/ui/screens/home/accounts_dashboard_screen.dart';
import 'package:ngoda/ui/screens/home/admin_dashboard_screen.dart';
import 'package:ngoda/ui/screens/home/agent_dashboard_screen.dart';
import 'package:ngoda/ui/screens/home/compliance_dashboard_screen.dart';

import 'package:ngoda/ui/screens/home/customer_dashboard_screen.dart';
import 'package:ngoda/ui/screens/home/finance_dashboard_screen.dart';
import 'package:ngoda/ui/screens/home/merchant_dashboard_screen.dart';
import 'package:ngoda/ui/screens/home/treasury_dashboard_screen.dart';
import 'package:ngoda/ui/screens/home/vendor_dashboard_screen.dart';

class DashboardRouter extends ConsumerWidget {
  const DashboardRouter({super.key});

  static final Logger _log = Logger('DashboardRouter');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = getCurrentUser();

    final role = user.role?.trim().toLowerCase();

    _log.fine('Dashboard role: $role');

    final dashboard = _dashboardForRole(role);

    if (dashboard != null) {
      return dashboard;
    }

    /*
     * Prevent multiple invalid-role dialogs from
     * being scheduled if this widget rebuilds
     * before logout completes.
     */
    final roleErrorShown = ref.watch(roleErrorShownProvider);

    if (!roleErrorShown) {
      ref.read(roleErrorShownProvider.notifier).markShown();

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!context.mounted) {
          return;
        }

        _handleInvalidRole(context, ref);
      });
    }

    return const SizedBox.expand();
  }

  static Widget? _dashboardForRole(String? role) {
    return switch (role) {
      'customer' => const CustomerDashboardScreen(),

      'admin' => const AdminDashboardScreen(),
      'agent' => const AgentDashboardScreen(),

      'finance' => const FinanceDashboardScreen(),

      'treasury' => const TreasuryDashboardScreen(),
      'accounts' => const AccountsDashboardScreen(),
      'merchant' => const MerchantDashboardScreen(),
      'vendor' => const VendorDashboardScreen(),

      'compliance' => const ComplianceDashboardScreen(),
      _ => null,
    };
  }

  static Future<void> _handleInvalidRole(
    BuildContext context,
    WidgetRef ref,
  ) async {
    try {
      await DialogService.error(
        context,
        message: 'User role not defined. Please login again.',
      );

      if (!context.mounted) {
        return;
      }

      // await ref.read(authProvider.notifier).logout('Invalid Role');
    } finally {
      ref.read(roleErrorShownProvider.notifier).reset();
    }
  }
}
