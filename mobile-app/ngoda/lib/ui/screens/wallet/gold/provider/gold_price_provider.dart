import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ngoda/data_models/core/result.dart';
import 'package:ngoda/ui/screens/wallet/gold/service/gold_api_service_provider.dart';

final goldPriceProvider = FutureProvider.autoDispose<R<double>>((ref) async {
  try {
    final api = ref.read(goldApiServiceProvider);

    final price = await api.getGoldPrice();

    return R(result: price);
  } catch (error) {
    return R(error: error.toString());
  }
});
