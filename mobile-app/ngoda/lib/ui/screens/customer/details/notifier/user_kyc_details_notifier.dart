import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ngoda/data_models/kyc/user_kyc_details.dart';

import 'package:ngoda/ui/enums/enums.dart';
import 'package:ngoda/ui/screens/customer/details/services/user_details_api_service_provider.dart';
import 'package:ngoda/ui/screens/customer/details/state/user_details_transaction_state.dart';

class UserKycDetailsNotifier extends Notifier<UserDetailsTransactionState> {
  @override
  UserDetailsTransactionState build() {
    return const UserDetailsTransactionState();
  }

  void initKyc(UserKycDetails? kyc) {
    state = state.copyWith(
      userKycDetails:
          kyc ??
          const UserKycDetails(
            idType: null,
            idNumber: null,
            expiryDate: null,
            occupation: null,
            sourceOfFunds: null,
            taxNumber: null,
            status: null,
          ),
      error: null,
    );

    _validateKyc();
  }

  void updateIdentificationType(IdentificationType? value) {
    final kyc = state.userKycDetails;

    if (kyc == null || value == null) {
      return;
    }

    state = state.copyWith(
      userKycDetails: kyc.copyWith(idType: value.apiValue),
    );

    _validateKyc();
  }

  void updateIdNumber(String value) {
    final kyc = state.userKycDetails;

    if (kyc == null) {
      return;
    }

    state = state.copyWith(userKycDetails: kyc.copyWith(idNumber: value));

    _validateKyc();
  }

  void updateExpiryDate(DateTime value) {
    final kyc = state.userKycDetails;

    if (kyc == null) {
      return;
    }

    state = state.copyWith(userKycDetails: kyc.copyWith(expiryDate: value));

    _validateKyc();
  }

  void updateOccupation(String value) {
    final kyc = state.userKycDetails;

    if (kyc == null) {
      return;
    }

    state = state.copyWith(userKycDetails: kyc.copyWith(occupation: value));

    _validateKyc();
  }

  void updateSourceOfFunds(SourceOfFundsType? value) {
    final kyc = state.userKycDetails;

    if (kyc == null || value == null) {
      return;
    }

    state = state.copyWith(
      userKycDetails: kyc.copyWith(sourceOfFunds: value.apiValue),
    );

    _validateKyc();
  }

  void updateTaxNumber(String value) {
    final kyc = state.userKycDetails;

    if (kyc == null) {
      return;
    }

    state = state.copyWith(userKycDetails: kyc.copyWith(taxNumber: value));

    _validateKyc();
  }

  void _validateKyc() {
    final kyc = state.userKycDetails;

    if (kyc == null) {
      state = state.copyWith(isValid: false, error: null);

      return;
    }

    final hasRequiredFields =
        kyc.idType?.trim().isNotEmpty == true &&
        kyc.idNumber?.trim().isNotEmpty == true &&
        kyc.expiryDate != null &&
        kyc.occupation?.trim().isNotEmpty == true &&
        kyc.sourceOfFunds?.trim().isNotEmpty == true;

    if (!hasRequiredFields) {
      state = state.copyWith(isValid: false, error: null);

      return;
    }

    final expiryDate = kyc.expiryDate!;

    final expiry = DateTime(expiryDate.year, expiryDate.month, expiryDate.day);

    final now = DateTime.now();

    final today = DateTime(now.year, now.month, now.day);

    if (expiry.isBefore(today)) {
      state = state.copyWith(
        isValid: false,
        error: 'Identification document has expired',
      );

      return;
    }

    state = state.copyWith(isValid: true, error: null);
  }

  Future<void> updateUserKyc() async {
    final kyc = state.userKycDetails;

    if (kyc == null || !state.isValid) {
      return;
    }

    state = state.copyWith(isLoading: true, error: null);

    try {
      final service = ref.read(userDetailsApiServiceProvider);

      await service.updateUserKyc(userKyc: kyc);

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
