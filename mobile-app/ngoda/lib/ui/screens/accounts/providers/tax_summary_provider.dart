import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ngoda/data_models/core/result.dart';
import 'package:ngoda/data_models/tax/tax_summary.dart';
import 'package:ngoda/ui/screens/accounts/services/accounts_api_service_provider.dart';

final taxSummaryProvider = FutureProvider.family
    .autoDispose<R<TaxSummary>, List<String>>((ref, status) async {
      try {
        final api = ref.read(accountsApiServiceProvider);
        final response = await api.fetchGovernmentTaxSummary(status);
        return R(result: response);
      } catch (e) {
        return R(error: e.toString());
      }
    });
