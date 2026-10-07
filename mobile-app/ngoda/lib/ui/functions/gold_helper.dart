import 'package:ngoda/data_models/customer/loan_summary.dart';
import 'package:ngoda/data_models/gold/gold_metrics.dart';

GoldMetrics computeGoldMetrics(LoanSummary loanSummary) {
  final totalGold = loanSummary.gold.total.grams;
  final totalGoldUsd = loanSummary.gold.total.usdValue;
  final locked = loanSummary.gold.locked.grams;
  final lockedUsd = loanSummary.gold.locked.usdValue;
  final available = loanSummary.gold.available.grams;
  final availableUsd = loanSummary.gold.available.usdValue;
  return GoldMetrics(
    total: totalGold,
    totalUsd: totalGoldUsd,
    locked: locked,
    lockedUsd: lockedUsd,
    available: available,
    availableUsd: availableUsd,
  );
}
