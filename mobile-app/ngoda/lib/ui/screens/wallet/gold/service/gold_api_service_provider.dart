import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ngoda/core/providers/supabse_functions_provider.dart';
import 'package:ngoda/ui/screens/wallet/gold/service/gold_api_service.dart';

final goldApiServiceProvider = Provider<GoldApiService>((ref) {
  final functions = ref.watch(supabaseFunctionServiceProvider);

  return GoldApiService(functions);
});
