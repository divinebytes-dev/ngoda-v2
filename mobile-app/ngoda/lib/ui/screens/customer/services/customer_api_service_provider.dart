import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ngoda/core/providers/supabse_functions_provider.dart';
import 'package:ngoda/ui/screens/customer/services/customer_api_service.dart';

final customerApiServiceProvider = Provider<CustomerApiService>((ref) {
  final functions = ref.read(supabaseFunctionServiceProvider);

  return CustomerApiService(functions);
});
