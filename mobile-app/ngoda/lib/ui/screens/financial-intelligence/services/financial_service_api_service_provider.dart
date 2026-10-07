import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ngoda/core/providers/supabse_functions_provider.dart';
import 'package:ngoda/ui/screens/financial-intelligence/services/financial_intelligence_api_service.dart';

final financialIntelligenceApiServiceProvider =
    Provider<FinancialIntelligenceApiService>((ref) {
      final functions = ref.read(supabaseFunctionServiceProvider);

      return FinancialIntelligenceApiService(functions);
    });
