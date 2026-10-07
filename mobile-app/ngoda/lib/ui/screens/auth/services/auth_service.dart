import 'package:logging/logging.dart';
import 'package:ngoda/data_models/auth/password_reset_verification.dart';
import 'package:ngoda/ui/screens/auth/services/auth_api_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AuthService {
  final AuthApiService apiService;

  final Logger _log = Logger('AuthService');

  AuthService({required this.apiService});

  SupabaseClient get _supabase => Supabase.instance.client;

  Future<void> register({
    String? email,
    required String phone,
    required String password,
    required String countryCode,
    String? uplinerCode,
  }) async {
    await apiService.register(
      email: email,
      phone: phone,
      password: password,
      countryCode: countryCode,
      uplinerCode: uplinerCode,
    );

    _log.fine('Registration completed.');
  }

  Future<void> login({
    required String identifier,
    required String password,
  }) async {
    final value = identifier.trim();

    final isEmail = value.contains('@');

    final response = await _supabase.auth.signInWithPassword(
      email: isEmail ? value : null,
      phone: isEmail ? null : value,
      password: password,
    );

    if (response.session == null) {
      throw Exception('Login failed');
    }

    _log.fine('Login completed.');
  }

  Future<void> requestPasswordReset({required String identifier}) async {
    await apiService.requestPasswordReset(identifier: identifier);

    _log.fine('Password reset requested.');
  }

  Future<PasswordResetVerification> verifyPasswordResetOtp({
    required String phone,
    required String otp,
  }) async {
    final response = await apiService.verifyPasswordResetOtp(
      phone: phone,
      otp: otp,
    );

    final verification = PasswordResetVerification.fromJson(response);

    if (!verification.verified) {
      throw Exception('OTP verification failed');
    }

    _log.fine('Password reset OTP verified.');

    return verification;
  }

  Future<void> completePasswordReset({required String newPassword}) async {
    await apiService.completePasswordReset(newPassword: newPassword);

    _log.fine('Password reset completed.');
  }
}
