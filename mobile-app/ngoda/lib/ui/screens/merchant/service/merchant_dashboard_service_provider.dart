import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ngoda/ui/screens/merchant/service/merchant_api_service_provider.dart';
import 'package:ngoda/ui/screens/merchant/service/merchant_dashboard_service.dart';

final merchantDashboardServiceProvider = Provider<MerchantDashboardService>((
  ref,
) {
  final api = ref.read(merchantApiServiceProvider);

  return MerchantDashboardService(api);
});
