import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import 'package:ngoda/ui/enums/enums.dart';
import 'package:ngoda/ui/screens/customer/details/services/user_details_api_service_provider.dart';
import 'package:ngoda/ui/screens/customer/details/state/user_details_transaction_state.dart';

class UserDocumentVerificationNotifier
    extends Notifier<UserDetailsTransactionState> {
  @override
  UserDetailsTransactionState build() {
    return const UserDetailsTransactionState();
  }

  Future<void> saveDocument({
    required VerificationDocumentType type,
    required XFile file,
  }) async {
    if (file.path.trim().isEmpty) {
      state = state.copyWith(
        isValid: false,
        error: 'Please select a document to upload',
      );

      return;
    }

    state = state.copyWith(
      verificationDocumentType: type,
      isValid: true,
      isLoading: true,
      error: null,
    );

    try {
      final service = ref.read(userDetailsApiServiceProvider);

      await service.updateDocumentVerification(type: type, file: file);

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

  void reset() {
    state = const UserDetailsTransactionState();
  }
}
