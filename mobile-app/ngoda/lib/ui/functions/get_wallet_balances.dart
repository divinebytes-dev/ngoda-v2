import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ngoda/data_models/wallet/wallet.dart';

import 'package:ngoda/ui/functions/get_current_user.dart';
import 'package:ngoda/ui/screens/agent/providers/agent_dashboard_provider.dart';
import 'package:ngoda/ui/screens/merchant/provider/merchant_dashboard_provider.dart';
import 'package:ngoda/ui/screens/vendor/provider/vendor_dashboard_provider.dart';

Map<String, double>? getAgentWalletBalance(WidgetRef ref) {
  final role = getCurrentUser().role?.trim().toLowerCase();

  switch (role) {
    case 'agent':
      final dashboard = ref.read(agentDashboardProvider).value;

      final result = dashboard?.result;

      if (result == null) {
        return null;
      }

      return Map.unmodifiable({
        for (final entry in result.agentWallet.currencyEntries)
          entry.key: entry.value.balance,
      });

    case 'merchant':
      final dashboard = ref.read(merchantDashboardProvider).value;

      final result = dashboard?.result;

      if (result == null) {
        return null;
      }

      return Map.unmodifiable({
        for (final entry in result.agentWallet.currencyEntries)
          entry.key: entry.value.balance,
      });

    case 'vendor':
      final dashboard = ref.read(vendorDashboardProvider).value;

      final result = dashboard?.result;

      if (result == null) {
        return null;
      }

      return Map.unmodifiable({
        for (final entry in result.agentWallet.currencyEntries)
          entry.key: entry.value.balance,
      });

    default:
      return null;
  }
}

Map<String, double>? getMerchantWalletBalance(WidgetRef ref) {
  final role = getCurrentUser().role?.trim().toLowerCase();

  switch (role) {
    case 'merchant':
      final dashboard = ref.read(merchantDashboardProvider).value;

      final result = dashboard?.result;

      if (result == null) {
        return const {};
      }

      return Map.unmodifiable({
        for (final entry in result.merchantWallet.currencyEntries)
          entry.key: entry.value.balance,
      });

    case 'vendor':
      final dashboard = ref.read(vendorDashboardProvider).value;

      final result = dashboard?.result;

      if (result == null) {
        return null;
      }

      return Map.unmodifiable({
        for (final entry in result.merchantWallet.currencyEntries)
          entry.key: entry.value.balance,
      });

    default:
      return null;
  }
}

bool isCreditAgent(WidgetRef ref) {
  final role = getCurrentUser().role?.trim().toLowerCase();

  switch (role) {
    case 'agent':
    // final dashboard = ref.read(agentDashboardProvider).value;

    // return dashboard?.result?.isCreditAgent ?? false;

    case 'merchant':
      final dashboard = ref.read(merchantDashboardProvider).value;

      return dashboard?.result?.isCreditAgent ?? false;

    case 'vendor':
      // final dashboard = ref.read(vendorDashboardProvider).value;

      // return dashboard?.result?.isCreditAgent ?? false;
      return false;

    default:
      return false;
  }
}
