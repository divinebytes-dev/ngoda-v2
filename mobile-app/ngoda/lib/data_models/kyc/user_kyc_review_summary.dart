import 'package:ngoda/ui/enums/enums.dart';

class UserKycReviewSummary {
  const UserKycReviewSummary({
    required this.userId,
    required this.firstName,
    required this.middleName,
    required this.surname,
    required this.email,
    required this.phone,
    required this.countryCode,
    required this.roleId,
    required this.role,
    required this.kycId,
    required this.kycStatus,
    required this.kycStartedAt,
    required this.kycUpdatedAt,
  });

  final String userId;

  final String? firstName;

  final String? middleName;

  final String? surname;

  final String? email;

  final String? phone;

  final String countryCode;

  final String roleId;

  final String role;

  final String? kycId;

  final KycReviewStatus kycStatus;

  final DateTime? kycStartedAt;

  final DateTime? kycUpdatedAt;

  factory UserKycReviewSummary.fromJson(Map<String, dynamic> json) {
    return UserKycReviewSummary(
      userId: json['user_id']?.toString().trim() ?? '',
      firstName: _nullableString(json['first_name']),
      middleName: _nullableString(json['middle_name']),
      surname: _nullableString(json['surname']),
      email: _nullableString(json['email']),
      phone: _nullableString(json['phone']),
      countryCode: json['country_code']?.toString().trim().toLowerCase() ?? '',
      roleId: json['role_id']?.toString().trim() ?? '',
      role: json['role']?.toString().trim().toLowerCase() ?? '',
      kycId: _nullableString(json['kyc_id']),
      kycStatus: KycReviewStatus.fromJson(json['kyc_status']?.toString()),
      kycStartedAt: _parseDate(json['kyc_started_at']),
      kycUpdatedAt: _parseDate(json['kyc_updated_at']),
    );
  }

  String get fullName {
    final parts = [
      firstName,
      middleName,
      surname,
    ].where((value) => value?.isNotEmpty == true);

    if (parts.isEmpty) {
      return 'Unknown User';
    }

    return parts.join(' ');
  }

  bool get hasKyc => kycId?.isNotEmpty == true;

  bool get hasKycStarted => kycStartedAt != null;

  static String? _nullableString(dynamic value) {
    if (value == null) {
      return null;
    }

    final result = value.toString().trim();

    return result.isEmpty ? null : result;
  }

  static DateTime? _parseDate(dynamic value) {
    if (value == null) {
      return null;
    }

    final result = value.toString().trim();

    if (result.isEmpty) {
      return null;
    }

    return DateTime.tryParse(result);
  }
}
