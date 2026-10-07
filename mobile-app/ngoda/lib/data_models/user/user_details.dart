import 'package:ngoda/data_models/kyc/user_kyc_details.dart';
import 'package:ngoda/data_models/kyc/user_verification_details.dart';
import 'package:ngoda/data_models/user/user_basic_profile.dart';
import 'package:ngoda/data_models/user/user_contact_details.dart';

class UserDetails {
  const UserDetails({
    required this.userId,
    required this.basicProfile,
    required this.contactDetails,
    required this.kycDetails,
    required this.verificationDocuments,
  });

  final String userId;

  final UserBasicProfile basicProfile;

  final UserContactDetails contactDetails;

  final UserKycDetails kycDetails;

  final UserVerificationDocuments verificationDocuments;

  factory UserDetails.fromJson(Map<String, dynamic> json) {
    final data = _asMap(json['data'], fallback: json);

    return UserDetails(
      userId: data['user_id']?.toString().trim() ?? '',
      basicProfile: UserBasicProfile.fromJson(_asMap(data['basic_profile'])),
      contactDetails: UserContactDetails.fromJson(
        _asMap(data['contact_details']),
      ),
      kycDetails: UserKycDetails.fromJson(_asMap(data['kyc_details'])),
      verificationDocuments: UserVerificationDocuments.fromJson(
        _asMap(data['verification_documents']),
      ),
    );
  }

  bool get hasUser => userId.isNotEmpty;

  String get fullName => basicProfile.fullName;

  String? get preferredContact => contactDetails.preferredContact;
}

Map<String, dynamic> _asMap(dynamic value, {Map<String, dynamic>? fallback}) {
  if (value is Map) {
    return Map<String, dynamic>.from(value);
  }

  return fallback ?? const {};
}
