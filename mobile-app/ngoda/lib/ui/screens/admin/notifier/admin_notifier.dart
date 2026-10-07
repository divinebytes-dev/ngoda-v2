import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';
import 'package:ngoda/data_models/admin/operational_country.dart';
import 'package:ngoda/data_models/currency/currency.dart';
import 'package:ngoda/ui/functions/get_identifier_type.dart';
import 'package:ngoda/ui/screens/admin/service/admin_api_service_provider.dart';
import 'package:ngoda/ui/screens/admin/state/admin_transactions_state.dart';

class AdminNotifier extends Notifier<AdminTransactionsState> {
  final Logger log = Logger('AdminNotifier');

  @override
  AdminTransactionsState build() {
    return const AdminTransactionsState();
  }

  Future<void> changeRole({required String email, required String role}) async {
    state = state.copyWith(isLoading: true, clearError: true);

    try {
      final service = ref.read(adminApiServiceProvider);

      await service.changeUserRole(email: email.trim(), role: role);

      state = state.copyWith(isLoading: false, clearError: true);
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());

      rethrow;
    }
  }

  Future<void> grandRole({required String role}) async {
    state = state.copyWith(isLoading: true, clearError: true);

    try {
      final service = ref.read(adminApiServiceProvider);

      await service.grandRole(role: role);

      state = state.copyWith(isLoading: false, clearError: true);
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());

      rethrow;
    }
  }

  Future<void> updateOperationalCountry() async {
    final country = state.country?.trim();
    final code = state.code?.trim();
    final callingCode = state.callingCode?.trim();

    if (!_isOperationalCountryValid(
      country: country,
      code: code,
      callingCode: callingCode,
    )) {
      state = state.copyWith(
        isValid: false,
        error: 'Please complete all required country fields',
      );
      return;
    }

    state = state.copyWith(isLoading: true, clearError: true);

    try {
      final service = ref.read(adminApiServiceProvider);

      await service.updateOperationalCountry(
        countryCode: code!,
        name: country!,
        callingCode: callingCode!,
        isActive: state.isActive,
      );

      state = state.copyWith(isLoading: false, clearError: true);
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());

      rethrow;
    }
  }

  Future<void> updateCountryCurrencies({
    required String countryCode,
    required String currencyCode,
    required bool isActive,
  }) async {
    if (countryCode.trim().isEmpty || currencyCode.trim().isEmpty) {
      state = state.copyWith(
        isValid: false,
        error: 'Please select a country and currency',
      );
      return;
    }

    state = state.copyWith(isLoading: true, clearError: true);

    try {
      final service = ref.read(adminApiServiceProvider);

      await service.updateCountryCurrencies(
        countryCode: countryCode.trim(),
        currencyCode: currencyCode.trim(),
        isActive: isActive,
      );

      state = state.copyWith(isLoading: false, clearError: true);
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());

      rethrow;
    }
  }

  Future<void> updateSupportedCurrencies({
    required String currencyCode,
    required String name,
    required String symbol,
    required String rateUrl,
    required bool isActive,
    required int decimals,
  }) async {
    if (!_isSupportedCurrencyValid(
      name: name,
      code: currencyCode,
      symbol: symbol,
      decimals: decimals,
      rateUrl: rateUrl,
    )) {
      state = state.copyWith(
        isValid: false,
        error: 'Please complete all required currency fields',
      );
      return;
    }

    state = state.copyWith(isLoading: true, clearError: true);

    try {
      final service = ref.read(adminApiServiceProvider);

      await service.updateSupportedCurrencies(
        currencyCode: currencyCode.trim(),
        name: name.trim(),
        symbol: symbol.trim(),
        rateUrl: rateUrl.trim(),
        isActive: isActive,
        decimals: decimals,
      );

      state = state.copyWith(isLoading: false, clearError: true);
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());

      rethrow;
    }
  }

  void updateRole(String value) {
    final role = value.trim();

    state = state.copyWith(
      role: role,
      isValid: _isUserRoleValid(email: state.email, role: role),
      clearError: true,
    );
  }

  void updateBlockchainRole(String value) {
    final role = value.trim();

    state = state.copyWith(
      role: role,
      isValid: role.isNotEmpty,
      clearError: true,
    );
  }

  void updateEmail(String value) {
    final email = value.trim();

    if (email.isEmpty) {
      state = state.copyWith(email: email, isValid: false, clearError: true);
      return;
    }

    final error = validateIdentifier(email);

    state = state.copyWith(
      email: email,
      isValid:
          error == null && _isUserRoleValid(email: email, role: state.role),
      error: error,
      clearError: error == null,
    );
  }

  void updateCountry(String value) {
    final country = value.trim();

    state = state.copyWith(
      country: country,
      isValid: _isOperationalCountryValid(
        country: country,
        code: state.code,
        callingCode: state.callingCode,
      ),
      clearError: true,
    );
  }

  void updateCode(String value) {
    final code = value.trim();

    state = state.copyWith(
      code: code,
      isValid: _isOperationalCountryValid(
        country: state.country,
        code: code,
        callingCode: state.callingCode,
      ),
      clearError: true,
    );
  }

  void updateCallingCode(String value) {
    final callingCode = value.trim();

    state = state.copyWith(
      callingCode: callingCode,
      isValid: _isOperationalCountryValid(
        country: state.country,
        code: state.code,
        callingCode: callingCode,
      ),
      clearError: true,
    );
  }

  void updateIsActive(bool value) {
    state = state.copyWith(
      isActive: value,
      isValid: _isOperationalCountryValid(
        country: state.country,
        code: state.code,
        callingCode: state.callingCode,
      ),
      clearError: true,
    );
  }

  void updateOpCountry(OperationalCountry value) {
    state = state.copyWith(
      operationalCountry: value,
      isValid: _isCountryCurrencyValid(
        country: value,
        currency: state.currency,
      ),
      clearError: true,
    );
  }

  void updateCurrency(Currency value) {
    state = state.copyWith(
      currency: value,
      isValid: _isCountryCurrencyValid(
        country: state.operationalCountry,
        currency: value,
      ),
      clearError: true,
    );
  }

  void updateName(String value) {
    final name = value.trim();

    state = state.copyWith(
      name: name,
      isValid: _isSupportedCurrencyValid(
        name: name,
        code: state.code,
        symbol: state.symbol,
        decimals: state.decimals,
        rateUrl: state.rateUrl,
      ),
      clearError: true,
    );
  }

  void updateCurrencyCode(String value) {
    final code = value.trim();

    state = state.copyWith(
      code: code,
      isValid: _isSupportedCurrencyValid(
        name: state.name,
        code: code,
        symbol: state.symbol,
        decimals: state.decimals,
        rateUrl: state.rateUrl,
      ),
      clearError: true,
    );
  }

  void updateSymbol(String value) {
    final symbol = value.trim();

    state = state.copyWith(
      symbol: symbol,
      isValid: _isSupportedCurrencyValid(
        name: state.name,
        code: state.code,
        symbol: symbol,
        decimals: state.decimals,
        rateUrl: state.rateUrl,
      ),
      clearError: true,
    );
  }

  void updateDecimals(String value) {
    final trimmed = value.trim();
    final decimals = int.tryParse(trimmed);

    if (trimmed.isEmpty) {
      state = state.copyWith(
        clearDecimals: true,
        isValid: false,
        clearError: true,
      );
      return;
    }

    if (decimals == null || decimals < 0) {
      state = state.copyWith(
        clearDecimals: true,
        isValid: false,
        error: 'Enter a valid number of decimal places',
      );
      return;
    }

    state = state.copyWith(
      decimals: decimals,
      isValid: _isSupportedCurrencyValid(
        name: state.name,
        code: state.code,
        symbol: state.symbol,
        decimals: decimals,
        rateUrl: state.rateUrl,
      ),
      clearError: true,
    );
  }

  void updateRateUrl(String value) {
    final rateUrl = value.trim();

    state = state.copyWith(
      rateUrl: rateUrl,
      isValid: _isSupportedCurrencyValid(
        name: state.name,
        code: state.code,
        symbol: state.symbol,
        decimals: state.decimals,
        rateUrl: rateUrl,
      ),
      clearError: true,
    );
  }

  void updateCurrencyIsActive(bool value) {
    state = state.copyWith(
      isActive: value,
      isValid: _isSupportedCurrencyValid(
        name: state.name,
        code: state.code,
        symbol: state.symbol,
        decimals: state.decimals,
        rateUrl: state.rateUrl,
      ),
      clearError: true,
    );
  }

  bool _isUserRoleValid({required String? email, required String? role}) {
    if (email == null ||
        email.trim().isEmpty ||
        role == null ||
        role.trim().isEmpty) {
      return false;
    }

    return validateIdentifier(email.trim()) == null;
  }

  bool _isOperationalCountryValid({
    required String? country,
    required String? code,
    required String? callingCode,
  }) {
    return country != null &&
        country.trim().isNotEmpty &&
        code != null &&
        code.trim().isNotEmpty &&
        callingCode != null &&
        callingCode.trim().isNotEmpty;
  }

  bool _isCountryCurrencyValid({
    required OperationalCountry? country,
    required Currency? currency,
  }) {
    return country != null && currency != null;
  }

  bool _isSupportedCurrencyValid({
    required String? name,
    required String? code,
    required String? symbol,
    required int? decimals,
    required String? rateUrl,
  }) {
    return name != null &&
        name.trim().isNotEmpty &&
        code != null &&
        code.trim().isNotEmpty &&
        symbol != null &&
        symbol.trim().isNotEmpty &&
        decimals != null &&
        decimals >= 0 &&
        rateUrl != null &&
        rateUrl.trim().isNotEmpty;
  }

  void reset() {
    state = const AdminTransactionsState();
  }
}
