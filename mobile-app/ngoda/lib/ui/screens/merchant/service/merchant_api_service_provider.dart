import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ngoda/core/providers/supabse_functions_provider.dart';

import 'package:ngoda/ui/screens/merchant/service/merchant_api_service.dart';

final merchantApiServiceProvider = Provider<MerchantApiService>((ref) {
  final functions = ref.read(supabaseFunctionServiceProvider);

  return MerchantApiService(functions);
});
