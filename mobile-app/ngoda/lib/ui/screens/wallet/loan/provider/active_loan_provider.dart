import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ngoda/data_models/loan/active_loan.dart';
import 'package:ngoda/data_models/core/result.dart';
import 'package:ngoda/ui/screens/wallet/loan/service/loan_api_service_provider.dart';

final activeLoansProvider = FutureProvider.autoDispose<R<List<ActiveLoan>>>((
  ref,
) async {
  try {
    final api = ref.read(loanApiServiceProvider);

    final loans = await api.fetchActiveLoans();

    return R(result: loans);
  } catch (error) {
    return R(error: error.toString());
  }
});
