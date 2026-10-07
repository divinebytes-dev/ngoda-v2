import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ngoda/core/providers/supabse_functions_provider.dart';
import 'package:ngoda/ui/screens/treasury/service/treasury_api_service.dart';

final treasuryApiServiceProvider = Provider<TreasuryApiService>((ref) {
  final functions = ref.read(supabaseFunctionServiceProvider);

  return TreasuryApiService(functions);
});
