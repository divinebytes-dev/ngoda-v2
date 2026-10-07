import 'package:ngoda/data_models/accounts/accounts_dashboard.dart';

Map<String, double> getAccountsBalances(AccountsDashboard? dashboard) {
  if (dashboard == null) {
    return const {};
  }

  return Map.unmodifiable({
    for (final entry in dashboard.bankNetCurrencyEntries)
      entry.key: entry.value,
  });
}
