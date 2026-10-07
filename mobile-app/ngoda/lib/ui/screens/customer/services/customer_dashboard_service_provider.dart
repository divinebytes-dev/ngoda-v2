import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ngoda/ui/screens/wallet/loan/service/loan_api_service_provider.dart';
import 'package:ngoda/ui/screens/customer/services/customer_api_service_provider.dart';
import 'package:ngoda/ui/screens/customer/services/customer_dashboard_service.dart';

final customerDashboardServiceProvider = Provider<CustomerDashboardService>((
  ref,
) {
  final userApi = ref.read(customerApiServiceProvider);
  final loanApi = ref.read(loanApiServiceProvider);

  return CustomerDashboardService(userApi, loanApi);
});
