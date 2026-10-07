import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ngoda/data_models/core/result.dart';
import 'package:ngoda/data_models/wallet/wallet_balance_summary.dart';
import 'package:ngoda/ui/screens/wallet/reports/services/mini_statement_api_service_provider.dart';

final walletSummaryProvider =
    FutureProvider.autoDispose<R<WalletBalanceSummary>>((ref) async {
      try {
        final api = ref.read(miniStatementApiServiceProvider);

        final response = await api.getWalletSummary();

        return R(result: response);
      } catch (error) {
        return R(error: error.toString());
      }
    });
