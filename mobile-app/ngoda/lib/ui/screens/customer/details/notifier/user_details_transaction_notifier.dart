import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ngoda/data_models/user/user_basic_profile.dart';
import 'package:ngoda/ui/enums/enums.dart';
import 'package:ngoda/ui/screens/customer/details/services/user_details_api_service_provider.dart';
import 'package:ngoda/ui/screens/customer/details/state/user_details_transaction_state.dart';

class UserDetailsTransactionNotifier
    extends Notifier<UserDetailsTransactionState> {
  @override
  UserDetailsTransactionState build() {
    return const UserDetailsTransactionState();
  }

  void initBasicProfile(UserBasicProfile? profile) {
    state = state.copyWith(
      userBasicProfile:
          profile ??
          const UserBasicProfile(
            firstName: null,
            middleName: null,
            surname: null,
            dateOfBirth: null,
            gender: null,
            nationality: null,
          ),
      error: null,
    );

    _validateBasicProfile();
  }

  void updateFirstName(String value) {
    final profile = state.userBasicProfile;

    if (profile == null) {
      return;
    }

    state = state.copyWith(
      userBasicProfile: profile.copyWith(firstName: value),
    );

    _validateBasicProfile();
  }

  void updateMiddleName(String value) {
    final profile = state.userBasicProfile;

    if (profile == null) {
      return;
    }

    state = state.copyWith(
      userBasicProfile: profile.copyWith(middleName: value),
    );

    _validateBasicProfile();
  }

  void updateSurname(String value) {
    final profile = state.userBasicProfile;

    if (profile == null) {
      return;
    }

    state = state.copyWith(userBasicProfile: profile.copyWith(surname: value));

    _validateBasicProfile();
  }

  void updateDateOfBirth(DateTime value) {
    final profile = state.userBasicProfile;

    if (profile == null) {
      return;
    }

    state = state.copyWith(
      userBasicProfile: profile.copyWith(dateOfBirth: value),
    );

    _validateBasicProfile();
  }

  void updateGender(GenderType? value) {
    final profile = state.userBasicProfile;

    if (profile == null || value == null) {
      return;
    }

    state = state.copyWith(userBasicProfile: profile.copyWith(gender: value));

    _validateBasicProfile();
  }

  void updateNationality(String value) {
    final profile = state.userBasicProfile;

    if (profile == null) {
      return;
    }

    state = state.copyWith(
      userBasicProfile: profile.copyWith(nationality: value),
    );

    _validateBasicProfile();
  }

  void _validateBasicProfile() {
    final profile = state.userBasicProfile;

    if (profile == null) {
      state = state.copyWith(isValid: false, error: null);

      return;
    }

    final isValid =
        profile.firstName?.trim().isNotEmpty == true &&
        profile.surname?.trim().isNotEmpty == true &&
        profile.dateOfBirth != null &&
        profile.gender != null &&
        profile.nationality?.trim().isNotEmpty == true;

    state = state.copyWith(isValid: isValid, error: null);
  }

  Future<void> updateUserDetails() async {
    final profile = state.userBasicProfile;

    if (profile == null || !state.isValid) {
      return;
    }

    state = state.copyWith(isLoading: true, error: null);

    try {
      final service = ref.read(userDetailsApiServiceProvider);

      await service.updateUserDetails(userBasicProfile: profile);

      state = state.copyWith(isLoading: false, error: null);
    } catch (error) {
      state = state.copyWith(isLoading: false, error: error.toString());

      rethrow;
    }
  }

  void reset() {
    state = const UserDetailsTransactionState();
  }
}
