import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ngoda/ui/screens/finance/services/finance_api_service_provider.dart';
import 'package:ngoda/ui/screens/finance/services/finance_dashboard_service.dart';

final financeDashboardServiceProvider = Provider<FinanceDashboardService>((
  ref,
) {
  final api = ref.read(financeApiServiceProvider);

  return FinanceDashboardService(api);
});
