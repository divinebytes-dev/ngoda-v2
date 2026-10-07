class DecodedUser {
  const DecodedUser({
    this.userId,
    this.email,
    this.phoneNumber,
    this.role,
    this.isAuthenticated = false,
  });

  final String? userId;
  final String? email;
  final String? phoneNumber;

  /// Role supplied by the authenticated backend/session.
  ///
  /// This deliberately remains a String and is not coupled
  /// to the frontend UserRole enum.
  final String? role;

  final bool isAuthenticated;

  bool get isUnauthenticated => !isAuthenticated;

  bool get hasUserId => userId?.isNotEmpty == true;

  bool get hasEmail => email?.isNotEmpty == true;

  bool get hasPhoneNumber => phoneNumber?.isNotEmpty == true;

  bool get hasRole => role?.isNotEmpty == true;

  @override
  String toString() {
    return 'DecodedUser('
        'userId: $userId, '
        'role: $role, '
        'isAuthenticated: $isAuthenticated'
        ')';
  }
}
