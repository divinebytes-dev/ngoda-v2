import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ngoda/data_models/core/result.dart';
import 'package:ngoda/data_models/operations/blockchain/incomplete_blockchain_transaction.dart';
import 'package:ngoda/data_models/params/blockchain_transaction_params.dart';
import 'package:ngoda/ui/screens/treasury/service/treasury_api_service_provider.dart';

final incompleteBlockainTrxProvider = FutureProvider.family
    .autoDispose<
      R<IncompleteBlockchainTransactions>,
      BlockchainTransactionParams
    >((ref, params) async {
      try {
        final api = ref.read(treasuryApiServiceProvider);

        final response = await api.fetchIncompleteBlockchainTransactions(
          params,
        );

        return R(result: response);
      } catch (error) {
        return R(error: error.toString());
      }
    });
