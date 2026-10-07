import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ngoda/data_models/core/result.dart';
import 'package:ngoda/data_models/params/mini_statement_params.dart';
import 'package:ngoda/data_models/payment/mini_statement.dart';
import 'package:ngoda/ui/screens/wallet/reports/services/mini_statement_api_service_provider.dart';

final miniStatementProvider = FutureProvider.autoDispose
    .family<R<MiniStatement>, MiniStatementParams>((ref, params) async {
      try {
        final api = ref.read(miniStatementApiServiceProvider);

        final response = await api.getMiniStatement(params);

        return R(result: response);
      } catch (error) {
        return R(error: error.toString());
      }
    });
