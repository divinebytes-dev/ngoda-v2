import 'package:ngoda/ui/enums/enums.dart';

extension UserRoleX on UserRole {
  static UserRole? fromString(String? value) {
    if (value == null) {
      return null;
    }

    final normalized = value.trim().toLowerCase();

    if (normalized.isEmpty) {
      return null;
    }

    for (final role in UserRole.values) {
      if (role.name.toLowerCase() == normalized) {
        return role;
      }
    }

    return null;
  }

  String get value => name;

  String get displayName {
    return name
        .replaceAll('_', ' ')
        .split(' ')
        .where((word) => word.isNotEmpty)
        .map((word) => '${word[0].toUpperCase()}${word.substring(1)}')
        .join(' ');
  }
}
