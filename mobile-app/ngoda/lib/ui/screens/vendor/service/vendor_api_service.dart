import 'package:ngoda/services/supabase_function_service.dart';

class VendorApiService {
  const VendorApiService(this._functions);

  final SupabaseFunctionService _functions;

  Future<Map<String, dynamic>> getDashboard() async {
    return _functions.invokeData(
      functionName: 'vendor-dashboard',
      invalidResponseMessage: 'Invalid vendor dashboard response',
    );
  }
}
