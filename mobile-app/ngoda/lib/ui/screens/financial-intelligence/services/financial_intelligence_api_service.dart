import 'package:ngoda/data_models/financial-intelligence/badges/financial_badge_list.dart';
import 'package:ngoda/data_models/financial-intelligence/financial_behaviour_overview_data.dart';
import 'package:ngoda/data_models/financial-intelligence/periodic_financial_behaviour.dart';
import 'package:ngoda/services/supabase_function_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class FinancialIntelligenceApiService {
  const FinancialIntelligenceApiService(this._functions);

  final SupabaseFunctionService _functions;

  Future<FinancialBehaviourOverviewData> getFinancialBehaviourSummary() async {
    final data = await _functions.invokeData(
      functionName: 'fetch-financial-behaviour',
      method: HttpMethod.get,
      invalidResponseMessage: 'Invalid financial behaviour response',
    );

    return FinancialBehaviourOverviewData.fromJson(data);
  }

  Future<PeriodicFinancialBehaviour> getFinancialPeriodicBehaviour() async {
    final data = await _functions.invokeData(
      functionName: 'fetch-periodic-financial-behaviour',
      method: HttpMethod.get,
      invalidResponseMessage: 'Invalid periodic financial behaviour response',
    );

    return PeriodicFinancialBehaviour.fromJson(data);
  }

  Future<FinancialBadgeList> getFinancialBadges() async {
    final data = await _functions.invokeData(
      functionName: 'fetch-financial-badges',
      method: HttpMethod.get,
      invalidResponseMessage: 'Invalid financial badges response',
    );

    return FinancialBadgeList.fromJson(data);
  }
}
