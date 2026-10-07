import 'package:ngoda/data_models/kyc/user_kyc_details.dart';
import 'package:ngoda/data_models/kyc/user_verification_document.dart';
import 'package:ngoda/data_models/user/user_basic_profile.dart';
import 'package:ngoda/data_models/user/user_contact_details.dart';

import 'package:ngoda/ui/enums/enums.dart';

class UserDetailsTransactionState {
  final String? id;

  final bool isLoading;

  final bool isValid;

  final String? error;

  final String? reference;

  final UserBasicProfile? userBasicProfile;

  final UserContactDetails? userContactDetails;

  final UserKycDetails? userKycDetails;

  final UserVerificationDocument? userVerificationDocument;

  final VerificationDocumentType? verificationDocumentType;

  const UserDetailsTransactionState({
    this.id,
    this.isLoading = false,
    this.isValid = false,
    this.error,
    this.reference,
    this.userBasicProfile,
    this.userContactDetails,
    this.userKycDetails,
    this.userVerificationDocument,
    this.verificationDocumentType,
  });

  UserDetailsTransactionState copyWith({
    String? id,
    bool? isLoading,
    bool? isValid,
    String? error,
    String? reference,
    UserBasicProfile? userBasicProfile,
    UserContactDetails? userContactDetails,
    UserKycDetails? userKycDetails,
    UserVerificationDocument? userVerificationDocument,
    VerificationDocumentType? verificationDocumentType,
  }) {
    return UserDetailsTransactionState(
      id: id ?? this.id,
      isLoading: isLoading ?? this.isLoading,
      isValid: isValid ?? this.isValid,

      /*
       * Error intentionally does not use ??.
       *
       * Passing:
       *
       * error: null
       *
       * clears an existing validation/API error.
       *
       * All Profile notifiers rely on this
       * behaviour after validation or a
       * successful transaction.
       */
      error: error,

      reference: reference ?? this.reference,
      userBasicProfile: userBasicProfile ?? this.userBasicProfile,
      userContactDetails: userContactDetails ?? this.userContactDetails,
      userKycDetails: userKycDetails ?? this.userKycDetails,
      userVerificationDocument:
          userVerificationDocument ?? this.userVerificationDocument,
      verificationDocumentType:
          verificationDocumentType ?? this.verificationDocumentType,
    );
  }
}
