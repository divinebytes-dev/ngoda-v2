import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ngoda/core/providers/supabse_functions_provider.dart';
import 'package:ngoda/ui/screens/wallet/reports/services/mini_statement_api_service.dart';

final miniStatementApiServiceProvider = Provider<MiniStatementApiService>((
  ref,
) {
  final functions = ref.read(supabaseFunctionServiceProvider);

  return MiniStatementApiService(functions);
});
