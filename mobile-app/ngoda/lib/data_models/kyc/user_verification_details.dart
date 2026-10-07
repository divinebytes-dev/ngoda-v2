import 'package:ngoda/data_models/kyc/user_verification_document.dart';

class UserVerificationDocuments {
  const UserVerificationDocuments({
    required this.idFront,
    required this.idBack,
    required this.proofOfAddress,
    required this.selfie,
    required this.verificationStatus,
  });

  final UserVerificationDocument? idFront;

  final UserVerificationDocument? idBack;

  final UserVerificationDocument? proofOfAddress;

  final UserVerificationDocument? selfie;

  /// Dynamic backend verification status.
  final String? verificationStatus;

  factory UserVerificationDocuments.fromJson(Map<String, dynamic> json) {
    return UserVerificationDocuments(
      idFront: _parseDocument(json['id_front']),
      idBack: _parseDocument(json['id_back']),
      proofOfAddress: _parseDocument(json['proof_of_address']),
      selfie: _parseDocument(json['selfie']),
      verificationStatus: _optionalString(
        json['verification_status'],
      )?.toLowerCase(),
    );
  }

  bool get hasIdFront => idFront != null;

  bool get hasIdBack => idBack != null;

  bool get hasProofOfAddress => proofOfAddress != null;

  bool get hasSelfie => selfie != null;

  bool get hasDocuments => documents.isNotEmpty;

  List<UserVerificationDocument> get documents {
    return List.unmodifiable(<UserVerificationDocument>[
      ?idFront,
      ?idBack,
      ?proofOfAddress,
      ?selfie,
    ]);
  }
}

UserVerificationDocument? _parseDocument(dynamic value) {
  if (value is! Map) {
    return null;
  }

  final json = Map<String, dynamic>.from(value);

  if (json.isEmpty) {
    return null;
  }

  return UserVerificationDocument.fromJson(json);
}

String? _optionalString(dynamic value) {
  final result = value?.toString().trim();

  if (result == null || result.isEmpty) {
    return null;
  }

  return result;
}
