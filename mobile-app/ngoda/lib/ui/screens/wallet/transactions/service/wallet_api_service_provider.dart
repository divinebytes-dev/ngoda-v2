import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ngoda/core/providers/supabse_functions_provider.dart';
import 'package:ngoda/ui/screens/wallet/transactions/service/wallet_api_service.dart';

final walletApiServiceProvider = Provider<WalletApiService>((ref) {
  final functions = ref.watch(supabaseFunctionServiceProvider);

  return WalletApiService(functions);
});
