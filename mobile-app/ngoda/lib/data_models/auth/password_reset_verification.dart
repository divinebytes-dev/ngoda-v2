import 'package:ngoda/services/number_conversion_service.dart';

class PasswordResetVerification {
  const PasswordResetVerification({
    required this.verified,
    required this.accessToken,
    required this.refreshToken,
    this.expiresIn,
    this.expiresAt,
  });

  final bool verified;

  final String accessToken;
  final String refreshToken;

  final int? expiresIn;
  final int? expiresAt;

  factory PasswordResetVerification.fromJson(Map<String, dynamic> json) {
    final verified = json['verified'];

    final accessToken = json['accessToken']?.toString().trim();

    final refreshToken = json['refreshToken']?.toString().trim();

    if (verified is! bool) {
      throw const FormatException(
        'Invalid password reset '
        'verification response: '
        'verified is missing.',
      );
    }

    if (accessToken == null || accessToken.isEmpty) {
      throw const FormatException(
        'Invalid password reset '
        'verification response: '
        'accessToken is missing.',
      );
    }

    if (refreshToken == null || refreshToken.isEmpty) {
      throw const FormatException(
        'Invalid password reset '
        'verification response: '
        'refreshToken is missing.',
      );
    }

    return PasswordResetVerification(
      verified: verified,
      accessToken: accessToken,
      refreshToken: refreshToken,
      expiresIn: NumberConversionService.toNullableInt(json['expiresIn']),
      expiresAt: NumberConversionService.toNullableInt(json['expiresAt']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'verified': verified,
      'accessToken': accessToken,
      'refreshToken': refreshToken,
      'expiresIn': expiresIn,
      'expiresAt': expiresAt,
    };
  }

  @override
  String toString() {
    return 'PasswordResetVerification('
        'verified: $verified, '
        'expiresIn: $expiresIn, '
        'expiresAt: $expiresAt'
        ')';
  }
}
