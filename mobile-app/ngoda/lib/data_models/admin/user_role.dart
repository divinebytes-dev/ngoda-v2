class UserRole {
  const UserRole({required this.name});

  final String name;

  factory UserRole.fromJson(Map<String, dynamic> json) {
    return UserRole(name: _normalize(json['name']?.toString() ?? ''));
  }

  factory UserRole.fromString(String value) {
    return UserRole(name: _normalize(value));
  }

  static String _normalize(String value) {
    return value.trim().toLowerCase();
  }
}

extension UserRoleListX on List<UserRole> {
  /// Role names as returned by the model.
  List<String> get names {
    return List.unmodifiable(map((role) => role.name));
  }

  /// Alphabetically sorted role names.
  List<String> get sortedNames {
    final result = [...names]..sort();

    return List.unmodifiable(result);
  }

  /// Role names prepared for simple display.
  List<String> get displayNames {
    return List.unmodifiable(map((role) => role.name.toUpperCase()));
  }

  /// Check whether a role exists.
  bool containsRole(String role) {
    final normalized = role.trim().toLowerCase();

    return any((item) => item.name == normalized);
  }

  /// Get a role by name.
  UserRole? getByName(String role) {
    final normalized = role.trim().toLowerCase();

    for (final item in this) {
      if (item.name == normalized) {
        return item;
      }
    }

    return null;
  }
}
