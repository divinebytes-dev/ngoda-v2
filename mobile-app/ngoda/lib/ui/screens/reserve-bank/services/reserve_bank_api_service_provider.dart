import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ngoda/core/providers/supabse_functions_provider.dart';
import 'package:ngoda/ui/screens/reserve-bank/services/reserve_bank_api_service.dart';

final reserveBankApiServiceProvider = Provider<ReserveBankApiService>((ref) {
  final functions = ref.read(supabaseFunctionServiceProvider);

  return ReserveBankApiService(functions);
});
