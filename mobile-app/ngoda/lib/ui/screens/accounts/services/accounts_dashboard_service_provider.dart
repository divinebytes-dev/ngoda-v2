import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ngoda/ui/screens/accounts/services/accounts_api_service_provider.dart';
import 'package:ngoda/ui/screens/accounts/services/accounts_dashboard_service.dart';

final accountsDashboardServiceProvider = Provider<AccountsDashboardService>((
  ref,
) {
  final accountsApi = ref.read(accountsApiServiceProvider);

  return AccountsDashboardService(accountsApi);
});
