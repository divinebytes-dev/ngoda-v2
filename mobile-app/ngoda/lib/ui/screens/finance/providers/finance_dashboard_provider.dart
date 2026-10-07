import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ngoda/data_models/finance/finance_dashboard.dart';
import 'package:ngoda/data_models/core/result.dart';
import 'package:ngoda/ui/screens/finance/services/finance_dashboard_service_provider.dart';

final financeDashboardProvider = FutureProvider<R<FinanceDashboard>>((
  ref,
) async {
  final service = ref.read(financeDashboardServiceProvider);

  return service.load();
});
