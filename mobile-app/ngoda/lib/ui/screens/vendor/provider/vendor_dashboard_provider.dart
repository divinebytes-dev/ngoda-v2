import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ngoda/data_models/core/result.dart';
import 'package:ngoda/data_models/vendor/vendor_dashboard.dart';
import 'package:ngoda/ui/screens/vendor/service/vendor_dashboard_service_provider.dart';

final vendorDashboardProvider = FutureProvider<R<VendorDashboard>>((ref) async {
  final service = ref.read(vendorDashboardServiceProvider);

  return service.load();
});
