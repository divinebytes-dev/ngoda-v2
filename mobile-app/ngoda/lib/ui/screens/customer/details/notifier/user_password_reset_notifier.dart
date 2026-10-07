import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ngoda/ui/screens/customer/details/services/user_details_api_service_provider.dart';
import 'package:ngoda/ui/screens/customer/details/state/user_details_transaction_state.dart';

class UserResetPasswordNotifier extends Notifier<UserDetailsTransactionState> {
  @override
  UserDetailsTransactionState build() {
    return const UserDetailsTransactionState();
  }

  bool validate({
    required String currentPassword,
    required String newPassword,
    required String confirmPassword,
  }) {
    String? error;

    if (currentPassword.isEmpty) {
      error = 'Current password is required';
    } else if (!_isValidPassword(newPassword)) {
      error =
          'Password must contain at least 8 characters, '
          'including uppercase, lowercase, number and '
          'special character';
    } else if (confirmPassword.isEmpty) {
      error = 'Please confirm your new password';
    } else if (newPassword != confirmPassword) {
      error = 'Passwords do not match';
    } else if (currentPassword == newPassword) {
      error = 'New password must be different from your current password';
    }

    state = state.copyWith(isValid: error == null, error: error);

    return error == null;
  }

  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
    required String confirmPassword,
  }) async {
    final isValid = validate(
      currentPassword: currentPassword,
      newPassword: newPassword,
      confirmPassword: confirmPassword,
    );

    if (!isValid) {
      return;
    }

    state = state.copyWith(isLoading: true, error: null);

    try {
      final service = ref.read(userDetailsApiServiceProvider);

      await service.resetPassword(
        currentPassword: currentPassword,
        newPassword: newPassword,
      );

      state = state.copyWith(isLoading: false, isValid: true, error: null);
    } catch (error) {
      state = state.copyWith(
        isLoading: false,
        isValid: false,
        error: error.toString(),
      );

      rethrow;
    }
  }

  bool _isValidPassword(String value) {
    return value.length >= 8 &&
        RegExp(r'[A-Z]').hasMatch(value) &&
        RegExp(r'[a-z]').hasMatch(value) &&
        RegExp(r'[0-9]').hasMatch(value) &&
        RegExp(r'[!@#$%^&*(),.?":{}|<>_\-+=]').hasMatch(value);
  }

  void reset() {
    state = const UserDetailsTransactionState();
  }
}
