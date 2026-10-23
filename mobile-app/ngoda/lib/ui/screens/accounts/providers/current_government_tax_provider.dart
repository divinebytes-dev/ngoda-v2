import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ngoda/data_models/core/result.dart';
import 'package:ngoda/data_models/params/current_tax_params.dart';
import 'package:ngoda/data_models/tax/current_government_tax.dart';
import 'package:ngoda/ui/screens/finance/services/finance_api_service_provider.dart';

final currentGovernmentTaxProvider = FutureProvider.family
    .autoDispose<R<CurrentGovernmentTax>, CurrentTaxParams>((ref, params) async {
      try {
        final api = ref.read(financeApiServiceProvider);
        final response = await api.fetchCurrentGovernmentTax(params);
        return R(result: response);
      } catch (e) {
        return R(error: e.toString());
      }
    });
