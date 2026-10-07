import 'package:ngoda/services/supabase_function_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AdminApiService {
  AdminApiService(this._functions);

  final SupabaseFunctionService _functions;

  Future<Map<String, dynamic>> getDashboard() async {
    return _functions.invokeData(
      functionName: 'admin-dashboard',
      method: HttpMethod.get,
      invalidResponseMessage: 'Invalid admin dashboard response',
    );
  }

  Future<Map<String, dynamic>> changeUserRole({
    required String email,
    required String role,
  }) async {
    return _functions.invokeData(
      functionName: 'change-user-role',
      body: {'email': email, 'new_role': role},
      invalidResponseMessage: 'Invalid change user role response',
    );
  }

  Future<Map<String, dynamic>> updateOperationalCountry({
    required String countryCode,
    required String name,
    required String callingCode,
    required bool isActive,
  }) async {
    return _functions.invokeData(
      functionName: 'upsert-operational-country',
      body: {
        'country_code': countryCode.toLowerCase(),
        'name': name,
        'calling_code': callingCode,
        'is_active': isActive,
      },
      invalidResponseMessage: 'Invalid operational country response',
    );
  }

  Future<Map<String, dynamic>> updateCountryCurrencies({
    required String countryCode,
    required String currencyCode,
    required bool isActive,
  }) async {
    return _functions.invokeData(
      functionName: 'upsert-country-currency',
      body: {
        'country_code': countryCode.toLowerCase(),
        'currency_code': currencyCode.toLowerCase(),
        'is_active': isActive,
      },
      invalidResponseMessage: 'Invalid country currency response',
    );
  }

  Future<Map<String, dynamic>> updateSupportedCurrencies({
    required String currencyCode,
    required String name,
    required String symbol,
    required String rateUrl,
    required bool isActive,
    required int decimals,
  }) async {
    return _functions.invokeData(
      functionName: 'upsert-supported-currency',
      body: {
        'currency_code': currencyCode.toLowerCase(),
        'decimals': decimals,
        'rate_url': rateUrl,
        'symbol': symbol,
        'name': name,
        'is_active': isActive,
      },
      invalidResponseMessage: 'Invalid supported currency response',
    );
  }

  Future<void> grandRole({required String role}) async {
    await _functions.invokeVoid(
      functionName: 'grant-token-role',
      body: {'role': role},
    );
  }
}
