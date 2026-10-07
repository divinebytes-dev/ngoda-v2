import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ngoda/core/providers/supabse_functions_provider.dart';
import 'package:ngoda/ui/screens/wallet/loan/service/loan_api_service.dart';

final loanApiServiceProvider = Provider<LoanApiService>((ref) {
  final functions = ref.watch(supabaseFunctionServiceProvider);

  return LoanApiService(functions);
});
