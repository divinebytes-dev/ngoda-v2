import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ngoda/data_models/user/user_contact_details.dart';
import 'package:ngoda/ui/functions/identifier_validation.dart';
import 'package:ngoda/ui/screens/customer/details/services/user_details_api_service_provider.dart';
import 'package:ngoda/ui/screens/customer/details/state/user_details_transaction_state.dart';

class UserContactsNotifier extends Notifier<UserDetailsTransactionState> {
  @override
  UserDetailsTransactionState build() {
    return const UserDetailsTransactionState();
  }

  void initContact(UserContactDetails? contacts) {
    state = state.copyWith(
      userContactDetails:
          contacts ??
          const UserContactDetails(
            email: null,
            phone: null,
            countryCode: null,
            countryName: null,
            residentialAddress: null,
            city: null,
            provinceState: null,
          ),
      error: null,
    );

    _validateContacts();
  }

  void updateEmail(String value) {
    final contacts = state.userContactDetails;

    if (contacts == null) {
      return;
    }

    state = state.copyWith(userContactDetails: contacts.copyWith(email: value));

    _validateContacts();
  }

  void updatePhone(String value) {
    final contacts = state.userContactDetails;

    if (contacts == null) {
      return;
    }

    state = state.copyWith(userContactDetails: contacts.copyWith(phone: value));

    _validateContacts();
  }

  void updateCountryCode(String value) {
    final contacts = state.userContactDetails;

    if (contacts == null) {
      return;
    }

    state = state.copyWith(
      userContactDetails: contacts.copyWith(countryCode: value),
    );

    _validateContacts();
  }

  void updateCountryName(String value) {
    final contacts = state.userContactDetails;

    if (contacts == null) {
      return;
    }

    state = state.copyWith(
      userContactDetails: contacts.copyWith(countryName: value),
    );

    _validateContacts();
  }

  void updateResidentialAddress(String value) {
    final contacts = state.userContactDetails;

    if (contacts == null) {
      return;
    }

    state = state.copyWith(
      userContactDetails: contacts.copyWith(residentialAddress: value),
    );

    _validateContacts();
  }

  void updateCity(String value) {
    final contacts = state.userContactDetails;

    if (contacts == null) {
      return;
    }

    state = state.copyWith(userContactDetails: contacts.copyWith(city: value));

    _validateContacts();
  }

  void updateProvinceState(String value) {
    final contacts = state.userContactDetails;

    if (contacts == null) {
      return;
    }

    state = state.copyWith(
      userContactDetails: contacts.copyWith(provinceState: value),
    );

    _validateContacts();
  }

  void _validateContacts() {
    final contacts = state.userContactDetails;

    if (contacts == null) {
      state = state.copyWith(isValid: false, error: null);

      return;
    }

    final hasRequiredFields =
        contacts.phone?.trim().isNotEmpty == true &&
        contacts.countryCode?.trim().isNotEmpty == true &&
        contacts.countryName?.trim().isNotEmpty == true &&
        contacts.residentialAddress?.trim().isNotEmpty == true &&
        contacts.city?.trim().isNotEmpty == true;

    if (!hasRequiredFields) {
      state = state.copyWith(isValid: false, error: null);

      return;
    }

    final email = contacts.email?.trim();

    if (email != null && email.isNotEmpty && !isValidEmail(email)) {
      state = state.copyWith(
        isValid: false,
        error: 'Please enter a valid email address',
      );

      return;
    }

    final phone = contacts.phone!.trim();

    if (!isValidPhoneNumber(phone)) {
      state = state.copyWith(
        isValid: false,
        error: 'Please enter a valid phone number',
      );

      return;
    }

    state = state.copyWith(isValid: true, error: null);
  }

  Future<void> updateUserContacts() async {
    final contacts = state.userContactDetails;

    if (contacts == null || !state.isValid) {
      return;
    }

    state = state.copyWith(isLoading: true, error: null);

    try {
      final service = ref.read(userDetailsApiServiceProvider);

      await service.updateUserContacts(userContacts: contacts);

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
