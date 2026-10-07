import 'package:ngoda/services/supabase_function_service.dart';

class CustomerApiService {
  const CustomerApiService(this._functions);

  final SupabaseFunctionService _functions;

  Future<Map<String, dynamic>> getDashboard() async {
    return _functions.invokeData(
      functionName: 'customer-dashboard',
      invalidResponseMessage: 'Invalid customer dashboard response',
    );
  }

  Future<String> getUserKey() async {
    return _functions.invokeDataValue<String>(
      functionName: 'wallet-key',
      invalidResponseMessage: 'Invalid wallet key response',
    );
  }

  Future<String> getReferralCode() async {
    return _functions.invokeDataValue<String>(
      functionName: 'referral-code',
      invalidResponseMessage: 'Invalid referral code response',
    );
  }
}
