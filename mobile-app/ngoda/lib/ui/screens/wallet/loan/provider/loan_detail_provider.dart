import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ngoda/data_models/loan/loan_detail.dart';
import 'package:ngoda/data_models/core/result.dart';
import 'package:ngoda/ui/screens/wallet/loan/service/loan_api_service_provider.dart';

final loanDetailsProvider = FutureProvider.autoDispose
    .family<R<LoanDetails>, String>((ref, loanId) async {
      try {
        final api = ref.read(loanApiServiceProvider);

        final details = await api.fetchLoanEntries(loanId);

        return R(result: details);
      } catch (error) {
        return R(error: error.toString());
      }
    });
