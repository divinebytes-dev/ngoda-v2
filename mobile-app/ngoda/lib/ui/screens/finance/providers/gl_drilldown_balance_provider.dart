import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ngoda/data_models/core/result.dart';
import 'package:ngoda/data_models/gl/gl_drilldown.dart';
import 'package:ngoda/data_models/params/gl_drilldown_params.dart';
import 'package:ngoda/ui/screens/finance/services/finance_api_service_provider.dart';

final glDrilldownBalanceProvider = FutureProvider.autoDispose
    .family<R<GLDrilldown>, GlDrilldownParams>((ref, glParams) async {
      try {
        final api = ref.read(financeApiServiceProvider);
        final response = await api.fetchDrilldownGlBalance(glParams);
        return R(result: response);
      } catch (err) {
        return R(error: err.toString());
      }
    });
