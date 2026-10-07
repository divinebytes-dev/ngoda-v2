import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ngoda/data_models/admin/admin_dashboard.dart';
import 'package:ngoda/data_models/core/result.dart';
import 'package:ngoda/ui/screens/admin/service/admin_dashboard_service_provider.dart';

final adminDashboardProvider = FutureProvider<R<AdminDashboard>>((ref) async {
  final service = ref.read(adminDashboardServiceProvider);

  return service.load();
});
