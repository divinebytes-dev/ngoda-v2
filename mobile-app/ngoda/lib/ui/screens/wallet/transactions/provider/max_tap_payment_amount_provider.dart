import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ngoda/data_models/payment/max_tap_payment_amount_list.dart';
import 'package:ngoda/data_models/core/result.dart';
import 'package:ngoda/ui/screens/wallet/transactions/service/wallet_api_service_provider.dart';

final maxTapPaymentAmountProvider =
    FutureProvider.autoDispose<R<MaxTapPaymentAmountList>>((ref) async {
      try {
        final api = ref.read(walletApiServiceProvider);
        final maximumAmounts = await api.getMaximumTapPaymentAmount();

        return R(result: maximumAmounts);
      } catch (error) {
        return R(error: error.toString());
      }
    });
