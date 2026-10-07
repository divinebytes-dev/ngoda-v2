import 'package:ngoda/data_models/country/supported_country.dart';
import 'package:ngoda/services/supabase_function_service.dart';

class AuthApiService {
  const AuthApiService(this._functions);

  final SupabaseFunctionService _functions;

  Future<List<SupportedCountry>> getCountries() async {
    final response = await _functions.invoke(
      functionName: 'operational-countries',
      invalidResponseMessage: 'Invalid operational countries response',
    );

    if (response['success'] != true) {
      throw Exception(
        response['message']?.toString() ??
            'Failed to fetch operational countries',
      );
    }

    final rawData = response['data'];

    if (rawData is! List) {
      throw Exception('Invalid operational countries response');
    }

    final countries = <SupportedCountry>[];

    for (final item in rawData) {
      if (item is! Map) {
        throw Exception('Invalid operational country response');
      }

      final json = Map<String, dynamic>.from(item);

      countries.add(SupportedCountry.fromJson(json));
    }

    return countries;
  }

  Future<Map<String, dynamic>> register({
    String? email,
    required String phone,
    required String password,
    required String countryCode,
    String? uplinerCode,
  }) async {
    return _functions.invoke(
      functionName: 'user-registration',
      body: {
        if (email != null && email.trim().isNotEmpty) 'email': email.trim(),
        'phone': phone.trim(),
        'password': password,
        'country_code': countryCode.trim(),
        if (uplinerCode != null && uplinerCode.trim().isNotEmpty)
          'upliner_code': uplinerCode.trim(),
      },
      invalidResponseMessage: 'Invalid user registration response',
    );
  }

  Future<Map<String, dynamic>> requestPasswordReset({
    required String identifier,
  }) async {
    return _functions.invoke(
      functionName: 'request-password-reset',
      body: {'identifier': identifier.trim()},
      invalidResponseMessage: 'Invalid password reset request response',
    );
  }

  Future<Map<String, dynamic>> verifyPasswordResetOtp({
    required String phone,
    required String otp,
  }) async {
    return _functions.invoke(
      functionName: 'verify-password-reset-otp',
      body: {'phone': phone.trim(), 'otp': otp.trim()},
      invalidResponseMessage: 'Invalid password reset OTP response',
    );
  }

  Future<Map<String, dynamic>> completePasswordReset({
    required String newPassword,
  }) async {
    return _functions.invoke(
      functionName: 'complete-password-reset',
      body: {'new_password': newPassword},
      invalidResponseMessage: 'Invalid password reset response',
    );
  }
}
