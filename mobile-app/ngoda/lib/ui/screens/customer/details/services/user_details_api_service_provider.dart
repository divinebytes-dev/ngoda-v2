import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ngoda/core/providers/supabse_functions_provider.dart';
import 'package:ngoda/ui/screens/customer/details/services/user_details_api_service.dart';

final userDetailsApiServiceProvider = Provider<UserDetailsApiService>((ref) {
  final functions = ref.watch(supabaseFunctionServiceProvider);

  return UserDetailsApiService(functions);
});
