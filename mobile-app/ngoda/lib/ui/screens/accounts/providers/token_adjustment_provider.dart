import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ngoda/data_models/core/result.dart';
import 'package:ngoda/data_models/treasury/token_adjustment.dart';
import 'package:ngoda/ui/screens/accounts/services/accounts_api_service_provider.dart';

final tokenAdjustmentProvider = FutureProvider.family
    .autoDispose<R<TokenAdjustment>, String>((ref, status) async {
      try {
        final api = ref.read(accountsApiServiceProvider);
        final response = await api.fetchTokenenAdjustmentData(status);
        return R(result: response);
      } catch (e) {
        return R(error: e.toString());
      }
    });
