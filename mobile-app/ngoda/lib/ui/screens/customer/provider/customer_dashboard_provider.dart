import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ngoda/data_models/core/result.dart';
import 'package:ngoda/data_models/customer/customer_dashboard.dart';

import 'package:ngoda/ui/screens/customer/services/customer_dashboard_service_provider.dart';

final customerDashboardProvider = FutureProvider<R<CustomerDashboard>>((
  ref,
) async {
  final service = ref.read(customerDashboardServiceProvider);
  return service.load();
});
