import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';
import 'package:ngoda/core/providers/analytics_service_provider.dart';
import 'package:ngoda/core/providers/hive_service_provider.dart';
import 'package:ngoda/core/providers/idle_service_provider.dart';
import 'package:ngoda/data_models/country/supported_country.dart';
import 'package:ngoda/services/hive_service.dart';
import 'package:ngoda/services/password_validator_service.dart';
import 'package:ngoda/services/user_presence_service.dart';
import 'package:ngoda/ui/enums/enums.dart';
import 'package:ngoda/ui/functions/app_reset.dart';
import 'package:ngoda/ui/functions/get_current_user.dart';
import 'package:ngoda/ui/functions/identifier_validation.dart';
import 'package:ngoda/ui/screens/auth/services/auth_service_provider.dart';
import 'package:ngoda/ui/screens/auth/state/user_auth_state.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AuthNotifier extends Notifier<UserAuthState> {
  final Logger _logger = Logger('AuthNotifier');

  SupabaseClient get _supabase => Supabase.instance.client;

  @override
  UserAuthState build() {
    final subscription = _supabase.auth.onAuthStateChange.listen(
      _onAuthStateChanged,
    );

    ref.onDispose(subscription.cancel);

    return const UserAuthState();
  }

  /*
   * ------------------------------------------------------------
   * SESSION
   * ------------------------------------------------------------
   */

  void _onAuthStateChanged(AuthState authState) {
    if (authState.session == null) {
      state = const UserAuthState();
      return;
    }

    if (state.isLocked) {
      state = state.copyWith(isLocked: false, clearError: true);
    }
  }

  /*
   * ------------------------------------------------------------
   * REGISTRATION FORM
   * ------------------------------------------------------------
   */

  void updateEmail(String value) {
    final email = value.trim();

    state = state.copyWith(email: email);

    _validateRegistration();
  }

  void updatePhoneNumber(String value) {
    final phone = value.trim();

    state = state.copyWith(phone: phone);

    _validateRegistration();
  }

  void updatePassword(String value) {
    state = state.copyWith(password: value);

    _validateRegistration();
  }

  void updateCountry(SupportedCountry country) {
    state = state.copyWith(country: country);

    _validateRegistration();
  }

  void setUplinerCode(String? code) {
    final value = code?.trim();

    state = state.copyWith(
      uplinerCode: value == null || value.isEmpty ? null : value,
    );
  }

  void _validateRegistration() {
    final email = state.email?.trim() ?? '';

    final phone = state.phone?.trim() ?? '';

    final password = state.password ?? '';

    String? error;

    if (email.isNotEmpty && !isValidEmail(email)) {
      error = 'Invalid email';
    } else if (phone.isNotEmpty && !isValidPhoneNumber(phone)) {
      error = 'Invalid phone number';
    } else if (password.isNotEmpty) {
      error = PasswordValidatorService.validate(password);
    }

    final valid =
        phone.isNotEmpty &&
        isValidPhoneNumber(phone) &&
        password.isNotEmpty &&
        PasswordValidatorService.isValid(password) &&
        state.country != null &&
        (email.isEmpty || isValidEmail(email));

    state = state.copyWith(
      isValid: valid,
      error: error,
      clearError: error == null,
    );
  }

  /*
   * ------------------------------------------------------------
   * REGISTRATION
   * ------------------------------------------------------------
   */

  Future<void> register() async {
    _validateRegistration();

    if (!state.isValid) {
      final message = state.error ?? 'Please complete all required fields';

      state = state.copyWith(error: message);

      throw Exception(message);
    }

    final phone = state.phone!.trim();

    final password = state.password!;

    final countryCode = state.country!.code;

    final emailValue = state.email?.trim();

    final email = emailValue == null || emailValue.isEmpty ? null : emailValue;

    state = state.copyWith(isLoading: true, clearError: true);

    try {
      final service = ref.read(authServiceProvider);

      await service.register(
        email: email,
        phone: phone,
        password: password,
        countryCode: countryCode,
        uplinerCode: state.uplinerCode,
      );

      ref
          .read(analyticsServiceProvider)
          .logUserRegistration(
            userData: {
              'country': countryCode,
              'platform': 'mobile',
              'source': 'playstore',
            },
          );

      state = const UserAuthState();
    } catch (error) {
      state = state.copyWith(isLoading: false, error: error.toString());

      rethrow;
    }
  }

  /*
   * ------------------------------------------------------------
   * LOGIN FORM
   * ------------------------------------------------------------
   */

  void updateLoginIdentifier(String value) {
    final identifier = value.trim();

    state = state.copyWith(identifier: identifier);

    _validateLogin();
  }

  void updateLoginPassword(String value) {
    state = state.copyWith(password: value);

    _validateLogin();
  }

  void _validateLogin() {
    final identifier = state.identifier?.trim() ?? '';

    final password = state.password ?? '';

    String? error;

    if (identifier.isNotEmpty) {
      final validIdentifier =
          isValidEmail(identifier) || isValidPhoneNumber(identifier);

      if (!validIdentifier) {
        error = 'Enter a valid email or phone number';
      }
    }

    final identifierValid =
        identifier.isNotEmpty &&
        (isValidEmail(identifier) || isValidPhoneNumber(identifier));

    final valid = identifierValid && password.isNotEmpty;

    state = state.copyWith(
      isValid: valid,
      error: error,
      clearError: error == null,
    );
  }

  /*
   * ------------------------------------------------------------
   * LOGIN
   * ------------------------------------------------------------
   */

  Future<void> login() async {
    _validateLogin();

    if (!state.isValid) {
      final message =
          state.error ?? 'Email or phone number and password are required';

      state = state.copyWith(error: message);

      throw Exception(message);
    }

    final identifier = state.identifier!.trim();

    final password = state.password!;

    state = state.copyWith(isLoading: true, clearError: true);

    try {
      final service = ref.read(authServiceProvider);

      await service.login(identifier: identifier, password: password);

      /*
       * Remove credentials from notifier
       * memory after successful login.
       *
       * Authentication itself is represented
       * by the Supabase session.
       */
      state = state.copyWith(
        isLoading: false,
        isValid: false,
        clearForm: true,
        clearError: true,
      );

      await ref
          .read(hiveServiceProvider)
          .saveItem<String>(
            HiveBoxName.lastLoginIdentifier,
            'lastLoginIdentifier',
            identifier,
          );
    } catch (error) {
      state = state.copyWith(isLoading: false, error: error.toString());

      rethrow;
    }
  }

  /*
   * ------------------------------------------------------------
   * PASSWORD RESET REQUEST
   * ------------------------------------------------------------
   */

  Future<PasswordResetMethod> requestPasswordReset({
    required String identifier,
  }) async {
    final value = identifier.trim();

    if (value.isEmpty) {
      const message = 'Email or phone number is required';

      state = state.copyWith(isValid: false, error: message);

      throw Exception(message);
    }

    final isEmail = isValidEmail(value);

    final isPhone = isValidPhoneNumber(value);

    if (!isEmail && !isPhone) {
      const message = 'Enter a valid email or phone number';

      state = state.copyWith(isValid: false, error: message);

      throw Exception(message);
    }

    final method = isEmail
        ? PasswordResetMethod.email
        : PasswordResetMethod.phone;

    state = state.copyWith(isLoading: true, clearError: true);

    try {
      final service = ref.read(authServiceProvider);

      await service.requestPasswordReset(identifier: value);

      state = state.copyWith(isLoading: false, clearError: true);

      return method;
    } catch (error) {
      state = state.copyWith(isLoading: false, error: error.toString());

      rethrow;
    }
  }

  /*
   * ------------------------------------------------------------
   * PHONE RESET OTP
   * ------------------------------------------------------------
   */

  Future<void> verifyPasswordResetOtp({
    required String phone,
    required String otp,
  }) async {
    final phoneValue = phone.trim();

    final otpValue = otp.trim();

    if (!isValidPhoneNumber(phoneValue)) {
      throw Exception('Invalid phone number');
    }

    if (!RegExp(r'^\d{6}$').hasMatch(otpValue)) {
      throw Exception('Invalid verification code');
    }

    state = state.copyWith(isLoading: true, clearError: true);

    try {
      final service = ref.read(authServiceProvider);

      final verification = await service.verifyPasswordResetOtp(
        phone: phoneValue,
        otp: otpValue,
      );

      await _supabase.auth.setSession(verification.refreshToken);

      if (_supabase.auth.currentSession == null) {
        throw Exception('Unable to establish password reset session');
      }

      state = state.copyWith(isLoading: false, clearError: true);
    } catch (error) {
      state = state.copyWith(isLoading: false, error: error.toString());

      rethrow;
    }
  }

  /*
   * ------------------------------------------------------------
   * COMPLETE PASSWORD RESET
   * ------------------------------------------------------------
   */

  Future<void> completePasswordReset({required String newPassword}) async {
    final passwordError = PasswordValidatorService.validate(newPassword);

    if (passwordError != null) {
      state = state.copyWith(error: passwordError);

      throw Exception(passwordError);
    }

    if (_supabase.auth.currentSession == null) {
      const message = 'Password reset session has expired. Please start again.';

      state = state.copyWith(error: message);

      throw Exception(message);
    }

    state = state.copyWith(isLoading: true, clearError: true);

    try {
      final service = ref.read(authServiceProvider);

      await service.completePasswordReset(newPassword: newPassword);

      await _supabase.auth.signOut();

      state = const UserAuthState();
    } catch (error) {
      state = state.copyWith(isLoading: false, error: error.toString());

      rethrow;
    }
  }

  /*
   * ------------------------------------------------------------
   * LOGOUT
   * ------------------------------------------------------------
   */

  Future<void> logout(String reason) async {
    if (state.isLoading) {
      return;
    }

    state = state.copyWith(isLoading: true, clearError: true);

    try {
      await UserPresenceService.stop();
      await _supabase.auth.signOut();

      ref.read(analyticsServiceProvider).logUserLogout('mobile');

      appResetKey.value++;

      state = UserAuthState(logoutReason: reason);
    } catch (error) {
      state = state.copyWith(isLoading: false, error: error.toString());

      rethrow;
    }
  }

  /*
   * ------------------------------------------------------------
   * APPLICATION LOCK
   * ------------------------------------------------------------
   */

  void lock() {
    if (!state.isAuthenticated || state.isLocked) {
      return;
    }

    state = state.copyWith(isLocked: true, clearError: true);
  }

  Future<void> unlock() async {
    if (!state.isLocked) {
      return;
    }

    state = state.copyWith(isLocked: false, clearError: true);

    ref.read(idleServiceProvider).userActivity();

    await _refreshAfterUnlock();
  }

  /*
   * ------------------------------------------------------------
   * POST-UNLOCK REFRESH
   * ------------------------------------------------------------
   */

  Future<void> _refreshAfterUnlock() async {
    final user = getCurrentUser();

    _logger.fine(
      'Refreshing data after unlock '
      'for ${user.role}',
    );

    // Refresh role-specific providers here
    // when required.
  }
}
