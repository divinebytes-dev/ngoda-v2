import 'package:ngoda/data_models/gamification/loyalty/transaction_loyalty_result.dart';
import 'package:ngoda/data_models/transaction/transaction_data.dart';
import 'package:ngoda/services/number_conversion_service.dart';

import 'package:ngoda/services/supabase_function_service.dart';

// import 'package:supabase_flutter/supabase_flutter.dart';

class GoldApiService {
  const GoldApiService(this._functions);

  final SupabaseFunctionService _functions;

  Future<double> getGoldPrice() async {
    final price = await _functions.invokeValue<String>(
      functionName: 'gold-price',
      invalidResponseMessage: 'Invalid gold price response',
    );

    return NumberConversionService.toDouble(price);
  }

  Future<TransactionLoyaltyResult> goldBuy({
    required TransactionData transactionData,
  }) async {
    final data = await _functions.invokeData(
      functionName: 'gold-buy',
      body: {'transaction': transactionData.toJson()},
      invalidResponseMessage: 'Invalid gold buy response',
    );

    /*
     * Preserve the current Gold Buy
     * response contract:
     *
     * data.loyalty
     */
    final loyalty = data['loyalty'];

    if (loyalty is! Map) {
      throw Exception('Invalid gold buy loyalty response');
    }

    return TransactionLoyaltyResult.fromJson(
      Map<String, dynamic>.from(loyalty),
    );
  }

  Future<void> goldSell({required TransactionData transactionData}) async {
    await _functions.invokeVoid(
      functionName: 'gold-sell',
      body: {'transaction': transactionData.toJson()},
    );
  }

  Future<void> goldTransfer({required TransactionData transactionData}) async {
    await _functions.invokeVoid(
      functionName: 'gold-transfer',
      body: {'transaction': transactionData.toJson()},
    );
  }
}
