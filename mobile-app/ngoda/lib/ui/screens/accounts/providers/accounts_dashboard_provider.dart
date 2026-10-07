import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ngoda/data_models/accounts/accounts_dashboard.dart';
import 'package:ngoda/data_models/core/result.dart';
import 'package:ngoda/ui/screens/accounts/services/accounts_dashboard_service_provider.dart';

final accountsDashboardProvider = FutureProvider<R<AccountsDashboard>>((
  ref,
) async {
  final service = ref.read(accountsDashboardServiceProvider);
  return service.load();
});
