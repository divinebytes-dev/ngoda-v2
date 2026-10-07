import 'package:ngoda/data_models/admin/operational_country.dart';
import 'package:ngoda/data_models/currency/currency.dart';

class AdminTransactionsState {
  final Currency? currency;
  final OperationalCountry? operationalCountry;

  final String? role;
  final String? email;

  final String? country;
  final String? code;
  final String? callingCode;

  final String? name;
  final String? symbol;
  final String? rateUrl;
  final int? decimals;

  final bool isValid;
  final bool isActive;
  final bool isLoading;

  final String? error;

  const AdminTransactionsState({
    this.currency,
    this.operationalCountry,
    this.role,
    this.email,
    this.country,
    this.code,
    this.callingCode,
    this.name,
    this.symbol,
    this.rateUrl,
    this.decimals,
    this.isValid = false,
    this.isActive = false,
    this.isLoading = false,
    this.error,
  });

  AdminTransactionsState copyWith({
    Currency? currency,
    OperationalCountry? operationalCountry,
    String? role,
    String? email,
    String? country,
    String? code,
    String? callingCode,
    String? name,
    String? symbol,
    String? rateUrl,
    int? decimals,
    bool? isValid,
    bool? isActive,
    bool? isLoading,
    String? error,
    bool clearCurrency = false,
    bool clearOperationalCountry = false,
    bool clearRole = false,
    bool clearEmail = false,
    bool clearCountry = false,
    bool clearCode = false,
    bool clearCallingCode = false,
    bool clearName = false,
    bool clearSymbol = false,
    bool clearRateUrl = false,
    bool clearDecimals = false,
    bool clearError = false,
  }) {
    return AdminTransactionsState(
      currency: clearCurrency ? null : currency ?? this.currency,
      operationalCountry: clearOperationalCountry
          ? null
          : operationalCountry ?? this.operationalCountry,
      role: clearRole ? null : role ?? this.role,
      email: clearEmail ? null : email ?? this.email,
      country: clearCountry ? null : country ?? this.country,
      code: clearCode ? null : code ?? this.code,
      callingCode: clearCallingCode ? null : callingCode ?? this.callingCode,
      name: clearName ? null : name ?? this.name,
      symbol: clearSymbol ? null : symbol ?? this.symbol,
      rateUrl: clearRateUrl ? null : rateUrl ?? this.rateUrl,
      decimals: clearDecimals ? null : decimals ?? this.decimals,
      isValid: isValid ?? this.isValid,
      isActive: isActive ?? this.isActive,
      isLoading: isLoading ?? this.isLoading,
      error: clearError ? null : error ?? this.error,
    );
  }
}
