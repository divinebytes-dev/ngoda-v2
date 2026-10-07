import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ngoda/core/providers/supabse_functions_provider.dart';
import 'package:ngoda/ui/screens/accounts/services/accounts_api_service.dart';

final accountsApiServiceProvider = Provider<AccountsApiService>((ref) {
  final functions = ref.read(supabaseFunctionServiceProvider);

  return AccountsApiService(functions);
});
