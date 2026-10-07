import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ngoda/data_models/core/result.dart';
import 'package:ngoda/data_models/wallet/multi_wallet_balance_summary.dart';
import 'package:ngoda/ui/screens/wallet/reports/services/mini_statement_api_service_provider.dart';

final multiWalletSummaryProvider =
    FutureProvider.autoDispose<R<MultiWalletBalanceSummary>>((ref) async {
      try {
        final api = ref.read(miniStatementApiServiceProvider);

        final response = await api.getMultiWalletSummary();

        return R(result: response);
      } catch (error) {
        return R(error: error.toString());
      }
    });
