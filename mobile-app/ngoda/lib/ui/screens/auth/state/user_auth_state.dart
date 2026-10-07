import 'package:ngoda/data_models/country/supported_country.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class UserAuthState {
  final bool isLoading;
  final bool isLocked;
  final bool isValid;

  final String? logoutReason;
  final String? identifier;
  final String? email;
  final String? phone;
  final String? password;
  final SupportedCountry? country;
  final String? uplinerCode;
  final String? error;

  const UserAuthState({
    this.isLoading = false,
    this.isLocked = false,
    this.isValid = false,
    this.logoutReason,
    this.identifier,
    this.email,
    this.phone,
    this.password,
    this.country,
    this.uplinerCode,
    this.error,
  });

  bool get isAuthenticated {
    return Supabase.instance.client.auth.currentSession != null;
  }

  UserAuthState copyWith({
    bool? isLoading,
    bool? isLocked,
    bool? isValid,
    String? logoutReason,
    String? identifier,
    String? email,
    String? phone,
    String? password,
    SupportedCountry? country,
    String? uplinerCode,
    String? error,
    bool clearError = false,
    bool clearForm = false,
  }) {
    return UserAuthState(
      isLoading: isLoading ?? this.isLoading,
      isLocked: isLocked ?? this.isLocked,
      isValid: clearForm ? false : isValid ?? this.isValid,
      logoutReason: logoutReason ?? this.logoutReason,
      identifier: clearForm ? null : identifier ?? this.identifier,
      email: clearForm ? null : email ?? this.email,
      phone: clearForm ? null : phone ?? this.phone,
      password: clearForm ? null : password ?? this.password,
      country: clearForm ? null : country ?? this.country,
      uplinerCode: clearForm ? null : uplinerCode ?? this.uplinerCode,
      error: clearError ? null : error ?? this.error,
    );
  }
}
