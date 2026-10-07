import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ngoda/data_models/core/result.dart';
import 'package:ngoda/data_models/gamification/ledger/loyalty_ledger_page.dart';
import 'package:ngoda/data_models/params/loyalty_ledger_params.dart';
import 'package:ngoda/ui/screens/gamification/services/gamification_api_service_provider.dart';

final loyaltyLedgerProvider = FutureProvider.autoDispose
    .family<R<LoyaltyLedgerPage>, LoyaltyLedgerParams>((ref, params) async {
      try {
        final api = ref.read(gamificationApiServiceProvider);

        final response = await api.fetchLoyaltyLedger(
          page: params.page,
          pageSize: params.pageSize,
        );

        return R(result: response);
      } catch (error) {
        return R(error: error.toString());
      }
    });
