import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ngoda/data_models/core/result.dart';
import 'package:ngoda/data_models/financial-intelligence/periodic_financial_behaviour.dart';
import 'package:ngoda/ui/screens/financial-intelligence/services/financial_service_api_service_provider.dart';

final periodicFinancialBehaviourProvider =
    FutureProvider.autoDispose<R<PeriodicFinancialBehaviour>>((ref) async {
      try {
        final api = ref.read(financialIntelligenceApiServiceProvider);

        final response = await api.getFinancialPeriodicBehaviour();

        return R(result: response);
      } catch (error) {
        return R(error: error.toString());
      }
    });
