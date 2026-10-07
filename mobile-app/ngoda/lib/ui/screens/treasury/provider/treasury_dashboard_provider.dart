import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ngoda/data_models/core/result.dart';
import 'package:ngoda/data_models/treasury/treasury_dashboard.dart';
import 'package:ngoda/ui/screens/treasury/service/treasury_dashboard_service_provider.dart';

final treasuryDashboardProvider = FutureProvider<R<TreasuryDashboard>>((
  ref,
) async {
  final service = ref.read(treasuryDashboardServiceProvider);

  return service.load();
});
