import 'package:ngoda/data_models/currency/currency.dart';
import 'package:ngoda/data_models/finance/finance_bucket.dart';
import 'package:ngoda/data_models/finance/finance_dashboard.dart';
import 'package:ngoda/data_models/treasury/treasury_dashboard.dart';
import 'package:ngoda/data_models/treasury/treasury_wallet.dart';

Map<String, double> getTreasuryBalances(FinanceDashboard? dashboard) {
  if (dashboard == null) {
    return const {};
  }

  return Map.unmodifiable({
    for (final entry in dashboard.summary.treasury.currencyEntries)
      entry.key: entry.value.balance,
  });
}

Map<String, double> getFinanceBalances(FinanceDashboard? dashboard) {
  if (dashboard == null) {
    return const {};
  }

  return Map.unmodifiable({
    for (final entry in dashboard.summary.bank.currencyEntries)
      entry.key: entry.value.balance,
  });
}

Currency? getCurrency(List<Currency> currencies, String code) {
  final normalizedCode = code.trim().toLowerCase();

  if (normalizedCode.isEmpty) {
    return null;
  }

  for (final currency in currencies) {
    if (currency.code.trim().toLowerCase() == normalizedCode) {
      return currency;
    }
  }

  return null;
}

Map<String, double> getTreasuryWallet(TreasuryDashboard? dashboard) {
  if (dashboard == null) {
    return const {};
  }

  return Map.unmodifiable({
    for (final entry in dashboard.treasuryWallet.currencyEntries)
      entry.key: entry.value.balance,
  });
}
