import 'package:ngoda/data_models/agent/agent_dashboard.dart';
import 'package:ngoda/data_models/customer/customer_dashboard.dart';
import 'package:ngoda/data_models/merchant/merchant_dashboard.dart';
import 'package:ngoda/data_models/vendor/vendor_dashboard.dart';

double computeUserNetPosition(
  CustomerDashboard dashboard,
  double availableGoldUsd,
) {
  final fiatTotal = dashboard.wallet.currencies.entries
      .where((entry) => entry.key.toLowerCase() != 'gold')
      .fold<double>(0.0, (sum, entry) => sum + entry.value.usdValue);

  return fiatTotal + availableGoldUsd;
}

double computeAgentNetPosition(AgentDashboard dashboard) {
  final agentFiatTotal = dashboard.agentWallet.currencies.entries
      .where((entry) => entry.key.toLowerCase() != 'gold')
      .fold<double>(0.0, (sum, entry) => sum + entry.value.usdValue);

  final customerFiatTotal = dashboard.customerWallet.currencies.entries
      .where((entry) => entry.key.toLowerCase() != 'gold')
      .fold<double>(0.0, (sum, entry) => sum + entry.value.usdValue);

  return agentFiatTotal + customerFiatTotal;
}

double computeMerchantNetPosition(MerchantDashboard dashboard) {
  final agentFiatTotal = dashboard.agentWallet.currencies.entries
      .where((entry) => entry.key.toLowerCase() != 'gold')
      .fold<double>(0.0, (sum, entry) => sum + entry.value.usdValue);

  final merchantFiatTotal = dashboard.merchantWallet.currencies.entries
      .where((entry) => entry.key.toLowerCase() != 'gold')
      .fold<double>(0.0, (sum, entry) => sum + entry.value.usdValue);

  return agentFiatTotal + merchantFiatTotal;
}

double computeVendorNetPosition(VendorDashboard dashboard) {
  final agentFiatTotal = dashboard.agentWallet.currencies.entries
      .where((entry) => entry.key.toLowerCase() != 'gold')
      .fold<double>(0.0, (sum, entry) => sum + entry.value.usdValue);

  final merchantFiatTotal = dashboard.merchantWallet.currencies.entries
      .where((entry) => entry.key.toLowerCase() != 'gold')
      .fold<double>(0.0, (sum, entry) => sum + entry.value.usdValue);

  final customerFiatTotal = dashboard.customerWallet.currencies.entries
      .where((entry) => entry.key.toLowerCase() != 'gold')
      .fold<double>(0.0, (sum, entry) => sum + entry.value.usdValue);

  return agentFiatTotal + merchantFiatTotal + customerFiatTotal;
}
