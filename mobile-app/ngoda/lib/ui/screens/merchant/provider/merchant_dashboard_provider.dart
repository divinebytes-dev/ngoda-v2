import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ngoda/data_models/merchant/merchant_dashboard.dart';
import 'package:ngoda/data_models/core/result.dart';
import 'package:ngoda/ui/screens/merchant/service/merchant_dashboard_service_provider.dart';

final merchantDashboardProvider = FutureProvider<R<MerchantDashboard>>((
  ref,
) async {
  final service = ref.read(merchantDashboardServiceProvider);

  return service.load();
});
