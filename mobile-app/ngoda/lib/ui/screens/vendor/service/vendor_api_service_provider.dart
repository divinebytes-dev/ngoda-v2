import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ngoda/core/providers/supabse_functions_provider.dart';
import 'package:ngoda/ui/screens/vendor/service/vendor_api_service.dart';

final vendorApiServiceProvider = Provider<VendorApiService>((ref) {
  final functions = ref.read(supabaseFunctionServiceProvider);

  return VendorApiService(functions);
});
