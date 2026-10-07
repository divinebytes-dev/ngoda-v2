import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ngoda/ui/screens/admin/service/admin_api_service_provider.dart';
import 'package:ngoda/ui/screens/admin/service/admin_dashboard_service.dart';

final adminDashboardServiceProvider = Provider<AdminDashboardService>((ref) {
  final adminApiService = ref.read(adminApiServiceProvider);

  return AdminDashboardService(adminApiService);
});
