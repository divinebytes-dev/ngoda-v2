import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ngoda/core/providers/supabse_functions_provider.dart';

import 'package:ngoda/ui/screens/finance/services/finance_api_service.dart';

final financeApiServiceProvider = Provider<FinanceApiService>((ref) {
  final functions = ref.read(supabaseFunctionServiceProvider);

  return FinanceApiService(functions);
});
