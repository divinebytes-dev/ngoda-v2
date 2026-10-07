import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ngoda/ui/screens/vendor/service/vendor_api_service_provider.dart';
import 'package:ngoda/ui/screens/vendor/service/vendor_dashboard_service.dart';

final vendorDashboardServiceProvider = Provider<VendorDashboardService>((ref) {
  final vendorApiService = ref.read(vendorApiServiceProvider);

  return VendorDashboardService(vendorApiService);
});
