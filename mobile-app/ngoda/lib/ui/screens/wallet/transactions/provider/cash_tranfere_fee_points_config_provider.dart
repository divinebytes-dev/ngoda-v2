import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ngoda/data_models/fee/cash_transfer_fee_configuration.dart';
import 'package:ngoda/data_models/core/result.dart';
import 'package:ngoda/ui/screens/wallet/transactions/service/wallet_api_service_provider.dart';

final cashTransferFeeConfigurationProvider =
    FutureProvider.autoDispose<R<CashTransferFeeConfiguration>>((ref) async {
      try {
        final api = ref.read(walletApiServiceProvider);
        final configuration = await api.fetchConfiguration();

        return R(result: configuration);
      } catch (error) {
        return R(error: error.toString());
      }
    });
