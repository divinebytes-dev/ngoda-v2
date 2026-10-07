import 'package:ngoda/services/supabase_function_service.dart';

class MerchantApiService {
  const MerchantApiService(this._functions);

  final SupabaseFunctionService _functions;

  Future<Map<String, dynamic>> getDashboard() async {
    return _functions.invokeData(
      functionName: 'merchant-dashboard',
      invalidResponseMessage: 'Invalid merchant dashboard response',
    );
  }
}
