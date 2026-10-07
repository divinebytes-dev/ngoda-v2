import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ngoda/data_models/core/result.dart';
import 'package:ngoda/ui/screens/finance/services/finance_api_service_provider.dart';

final lastInterestAccrualDateProvider =
    FutureProvider.autoDispose<R<DateTime?>>((ref) async {
      try {
        final api = ref.read(financeApiServiceProvider);

        final lastAccrualDate = await api.getLastAcrual();

        return R(result: lastAccrualDate);
      } catch (error) {
        return R(error: error.toString());
      }
    });
