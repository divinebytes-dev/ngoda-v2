import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ngoda/data_models/accounts/finance_document.dart';
import 'package:ngoda/data_models/core/result.dart';
import 'package:ngoda/ui/screens/finance/services/finance_api_service_provider.dart';

final financeDocumentProvider = FutureProvider.autoDispose
    .family<R<FinanceDocument>, String>((ref, documentNumber) async {
      try {
        final api = ref.read(financeApiServiceProvider);

        final response = await api.getFinanceDocument(documentNumber);

        return R(result: response);
      } catch (error) {
        return R(error: error.toString());
      }
    });
