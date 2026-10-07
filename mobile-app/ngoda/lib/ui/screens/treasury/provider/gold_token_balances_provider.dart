import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ngoda/data_models/core/result.dart';
import 'package:ngoda/data_models/gl/token_gl_summary.dart';
import 'package:ngoda/ui/screens/treasury/service/treasury_api_service_provider.dart';

final goldTokenBalancesProvider = FutureProvider.autoDispose<R<TokenGLSummary>>(
  (ref) async {
    try {
      final api = ref.read(treasuryApiServiceProvider);

      final response = await api.fetchTokenGlBalances();

      return R(result: response);
    } catch (error) {
      return R(error: error.toString());
    }
  },
);
