import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ngoda/data_models/loan/loan_preview.dart';
import 'package:ngoda/data_models/core/result.dart';
import 'package:ngoda/services/number_format_service.dart';
import 'package:ngoda/ui/screens/wallet/loan/service/loan_api_service_provider.dart';

final loanPreviewProvider = FutureProvider.autoDispose
    .family<R<LoanPreview>, String>((ref, amount) async {
      try {
        final api = ref.read(loanApiServiceProvider);

        final value = NumberFormatService.anyToDouble(amount.trim());

        final preview = await api.loanPreview(amount: value);

        return R(result: preview);
      } catch (error) {
        return R(error: error.toString());
      }
    });

// import 'package:flutter_riverpod/flutter_riverpod.dart';
// import 'package:ngoda/data_models/loan/loan_preview.dart';
// import 'package:ngoda/services/number_format_service.dart';
// import 'package:ngoda/ui/screens/customer/loan/service/loan_api_service_provider.dart';

// final loanPreviewProvider = FutureProvider.autoDispose
//     .family<LoanPreview, String>((ref, amount) async {
//       ref.keepAlive();
//       final api = ref.read(loanApiServiceProvider);

//       final response = await api.loanPreview(
//         amount: NumberFormatService.anyToDouble(amount.trim()),
//       );

//       return response;
//     });
