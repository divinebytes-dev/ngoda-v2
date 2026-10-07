import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ngoda/ui/screens/treasury/service/treasury_api_service_provider.dart';
import 'package:ngoda/ui/screens/treasury/service/treasury_dashboard_service.dart';

final treasuryDashboardServiceProvider = Provider<TreasuryDashboardService>((
  ref,
) {
  final treasuryApi = ref.read(treasuryApiServiceProvider);

  return TreasuryDashboardService(treasuryApi);
});
