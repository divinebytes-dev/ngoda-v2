import 'package:ngoda/data_models/admin/operational_country.dart';
import 'package:ngoda/data_models/admin/user_role.dart';
import 'package:ngoda/data_models/currency/currency.dart';
import 'package:ngoda/services/number_conversion_service.dart';

class AdminDashboard {
  AdminDashboard({
    required this.summary,
    required List<AdminCountrySummary> countries,
    required List<UserRole> roles,
    required List<OperationalCountry> operationalCountries,
    required List<Currency> supportedCurrencies,
    List<ActiveBlockchain> activeBlockchains = const [],
  }) : countries = List.unmodifiable(countries),
       roles = List.unmodifiable(roles),
       operationalCountries = List.unmodifiable(operationalCountries),
       supportedCurrencies = List.unmodifiable(supportedCurrencies),
       activeBlockchains = List.unmodifiable(activeBlockchains);

  final AdminDashboardTotals summary;

  final List<AdminCountrySummary> countries;

  /// Application roles configured in the backend.
  final List<UserRole> roles;

  final List<OperationalCountry> operationalCountries;

  final List<Currency> supportedCurrencies;

  /// Active EVM blockchains with a selected active network.
  final List<ActiveBlockchain> activeBlockchains;

  factory AdminDashboard.fromJson(Map<String, dynamic> json) {
    final rawData = json['data'];

    final data = rawData is Map ? Map<String, dynamic>.from(rawData) : json;

    return AdminDashboard(
      summary: AdminDashboardTotals.fromJson(_asMap(data['summary'])),
      countries: _parseList(data['countries'], AdminCountrySummary.fromJson),
      roles: _parseRoles(data['roles']),
      operationalCountries: _parseList(
        data['operationalCountries'],
        OperationalCountry.fromJson,
      ),
      supportedCurrencies: _parseList(
        data['supportedCurrencies'],
        Currency.fromJson,
      ),
      activeBlockchains: _parseList(
        data['activeBlockchains'],
        ActiveBlockchain.fromJson,
      ),
    );
  }

  factory AdminDashboard.empty() {
    return AdminDashboard(
      summary: const AdminDashboardTotals.empty(),
      countries: const [],
      roles: const [],
      operationalCountries: const [],
      supportedCurrencies: const [],
      activeBlockchains: const [],
    );
  }

  bool get isEmpty {
    return summary.totalUsers == 0 &&
        countries.isEmpty &&
        roles.isEmpty &&
        operationalCountries.isEmpty &&
        supportedCurrencies.isEmpty &&
        activeBlockchains.isEmpty;
  }

  bool get isNotEmpty => !isEmpty;

  int get totalUsers => summary.totalUsers;

  int get totalCreditAgents => summary.creditAgents;

  int get totalCountries => operationalCountries.length;

  int get totalActiveCountries {
    return operationalCountries.where((country) => country.isActive).length;
  }

  List<ActiveBlockchain> get sortedActiveBlockchains {
    final result = [...activeBlockchains]
      ..sort((first, second) {
        final nameComparison = first.name.compareTo(second.name);

        if (nameComparison != 0) {
          return nameComparison;
        }

        return first.code.compareTo(second.code);
      });

    return List.unmodifiable(result);
  }

  ActiveBlockchain? blockchainByCode(String code) {
    final normalized = code.trim().toLowerCase();

    for (final blockchain in activeBlockchains) {
      if (blockchain.code == normalized) {
        return blockchain;
      }
    }

    return null;
  }

  List<UserRole> get sortedRoles {
    final result = [...roles]
      ..sort((first, second) => first.name.compareTo(second.name));

    return List.unmodifiable(result);
  }

  bool hasRole(String role) {
    return roles.containsRole(role);
  }

  UserRole? getRole(String role) {
    return roles.getByName(role);
  }

  int roleCount(String role) {
    return summary.roleCount(role);
  }

  Map<String, int> get roleCounts {
    final result = <String, int>{};

    for (final role in roles) {
      result[role.name] = summary.roleCount(role.name);
    }

    return Map.unmodifiable(result);
  }

  List<AdminCountrySummary> get sortedCountries {
    final result = [
      ...countries,
    ]..sort((first, second) => first.countryCode.compareTo(second.countryCode));

    return List.unmodifiable(result);
  }

  List<AdminCountrySummary> get countriesByUserCount {
    final result = [...countries]
      ..sort((first, second) => second.totalUsers.compareTo(first.totalUsers));

    return List.unmodifiable(result);
  }

  List<OperationalCountry> get sortedOperationalCountries {
    final result = [...operationalCountries]
      ..sort((first, second) => first.name.compareTo(second.name));

    return List.unmodifiable(result);
  }

  List<OperationalCountry> get activeOperationalCountries {
    final result =
        operationalCountries.where((country) => country.isActive).toList()
          ..sort((first, second) => first.name.compareTo(second.name));

    return List.unmodifiable(result);
  }

  AdminCountrySummary? countrySummary(String countryCode) {
    final normalized = countryCode.trim().toLowerCase();

    for (final country in countries) {
      if (country.countryCode == normalized) {
        return country;
      }
    }

    return null;
  }

  OperationalCountry? operationalCountry(String countryCode) {
    return operationalCountries.getByCode(countryCode);
  }

  bool hasCountry(String countryCode) {
    return operationalCountry(countryCode) != null;
  }

  static List<T> _parseList<T>(
    dynamic value,
    T Function(Map<String, dynamic>) parser,
  ) {
    if (value is! List) {
      return const [];
    }

    return value
        .whereType<Map>()
        .map((item) => parser(Map<String, dynamic>.from(item)))
        .toList();
  }

  static Map<String, dynamic> _asMap(dynamic value) {
    if (value is Map) {
      return Map<String, dynamic>.from(value);
    }

    return const {};
  }

  static List<UserRole> _parseRoles(dynamic value) {
    if (value is! List) {
      return const [];
    }

    return value.whereType<String>().map(UserRole.fromString).toList();
  }
}

class ActiveBlockchain {
  const ActiveBlockchain({
    required this.code,
    required this.name,
    required this.chainId,
    required this.networkName,
  });

  final String code;

  final String name;

  final int chainId;

  final String networkName;

  factory ActiveBlockchain.fromJson(Map<String, dynamic> json) {
    return ActiveBlockchain(
      code: (json['code'] ?? '').toString().trim().toLowerCase(),
      name: (json['name'] ?? '').toString().trim(),
      chainId: NumberConversionService.toInt(json['chain_id']),
      networkName: (json['network_name'] ?? '').toString().trim(),
    );
  }

  String get displayName {
    if (networkName.isEmpty) {
      return name;
    }

    return '$name ($networkName)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is ActiveBlockchain &&
            other.code == code &&
            other.chainId == chainId;
  }

  @override
  int get hashCode => Object.hash(code, chainId);
}

class AdminDashboardTotals {
  AdminDashboardTotals({
    required this.totalUsers,
    required this.creditAgents,
    required Map<String, int> roleCounts,
  }) : roleCounts = Map.unmodifiable(roleCounts);

  const AdminDashboardTotals.empty()
    : totalUsers = 0,
      creditAgents = 0,
      roleCounts = const {};

  final int totalUsers;

  final int creditAgents;

  /// User counts keyed by backend role name.
  final Map<String, int> roleCounts;

  factory AdminDashboardTotals.fromJson(Map<String, dynamic> json) {
    return AdminDashboardTotals(
      totalUsers: NumberConversionService.toInt(json['totalUsers']),
      creditAgents: NumberConversionService.toInt(json['creditAgents']),
      roleCounts: _parseRoleCounts(json['roleCounts']),
    );
  }

  int roleCount(String role) {
    return roleCounts[role.trim().toLowerCase()] ?? 0;
  }

  bool containsRole(String role) {
    return roleCounts.containsKey(role.trim().toLowerCase());
  }

  int get totalUsersFromRoles {
    return roleCounts.values.fold(0, (total, count) => total + count);
  }

  bool get roleTotalsMatch {
    return totalUsersFromRoles == totalUsers;
  }

  bool get hasUsers => totalUsers > 0;

  bool get hasCreditAgents => creditAgents > 0;

  Map<String, int> get sortedRoleCounts {
    final entries = roleCounts.entries.toList()
      ..sort((first, second) => first.key.compareTo(second.key));

    return Map.unmodifiable(Map<String, int>.fromEntries(entries));
  }

  Map<String, int> get roleCountsByUserCount {
    final entries = roleCounts.entries.toList()
      ..sort((first, second) {
        final countComparison = second.value.compareTo(first.value);

        if (countComparison != 0) {
          return countComparison;
        }

        return first.key.compareTo(second.key);
      });

    return Map.unmodifiable(Map<String, int>.fromEntries(entries));
  }

  Map<String, int> get nonZeroRoleCounts {
    return Map.unmodifiable(
      Map<String, int>.fromEntries(
        roleCounts.entries.where((entry) => entry.value > 0),
      ),
    );
  }

  static Map<String, int> _parseRoleCounts(dynamic value) {
    if (value is! Map) {
      return const {};
    }

    final result = <String, int>{};

    for (final entry in value.entries) {
      final role = entry.key.toString().trim().toLowerCase();

      if (role.isEmpty) {
        continue;
      }

      result[role] = NumberConversionService.toInt(entry.value);
    }

    return result;
  }
}

class AdminCountrySummary {
  const AdminCountrySummary({required this.countryCode, required this.totals});

  final String countryCode;

  final AdminDashboardTotals totals;

  factory AdminCountrySummary.fromJson(Map<String, dynamic> json) {
    return AdminCountrySummary(
      countryCode: (json['countryCode'] ?? '').toString().trim().toLowerCase(),
      totals: AdminDashboardTotals.fromJson(json),
    );
  }

  int get totalUsers => totals.totalUsers;

  int get creditAgents => totals.creditAgents;

  Map<String, int> get roleCounts => totals.roleCounts;

  int roleCount(String role) {
    return totals.roleCount(role);
  }

  bool hasRole(String role) {
    return totals.containsRole(role);
  }

  Map<String, int> get nonZeroRoleCounts {
    return totals.nonZeroRoleCounts;
  }
}

// import 'package:ngoda/data_models/admin/operational_country.dart';
// import 'package:ngoda/data_models/admin/user_role.dart';
// import 'package:ngoda/data_models/currency/currency.dart';
// import 'package:ngoda/services/number_conversion_service.dart';

// class AdminDashboard {
//   AdminDashboard({
//     required this.summary,
//     required List<AdminCountrySummary> countries,
//     required List<UserRole> roles,
//     required List<OperationalCountry> operationalCountries,
//     required List<Currency> supportedCurrencies,
//   }) : countries = List.unmodifiable(countries),
//        roles = List.unmodifiable(roles),
//        operationalCountries = List.unmodifiable(operationalCountries),
//        supportedCurrencies = List.unmodifiable(supportedCurrencies);

//   final AdminDashboardTotals summary;

//   final List<AdminCountrySummary> countries;

//   /// Roles configured in the backend.
//   ///
//   /// These are deliberately kept separate from the frontend
//   /// UserRole enum used for application navigation/behaviour.
//   final List<UserRole> roles;

//   final List<OperationalCountry> operationalCountries;

//   final List<Currency> supportedCurrencies;

//   factory AdminDashboard.fromJson(Map<String, dynamic> json) {
//     final rawData = json['data'];

//     final data = rawData is Map ? Map<String, dynamic>.from(rawData) : json;
//     final countries = _parseList(
//       data['countries'],
//       AdminCountrySummary.fromJson,
//     );
//     final opCountries = _parseList(
//       data['operationalCountries'],
//       OperationalCountry.fromJson,
//     );
//     final roles = _parseRoles(data['roles']);
//     final supCurrencies = _parseList(
//       data['supportedCurrencies'],
//       Currency.fromJson,
//     );

//     return AdminDashboard(
//       summary: AdminDashboardTotals.fromJson(_asMap(data['summary'])),
//       countries: countries,
//       roles: roles,
//       operationalCountries: opCountries,
//       supportedCurrencies: supCurrencies,
//     );
//   }

//   factory AdminDashboard.empty() {
//     return AdminDashboard(
//       summary: const AdminDashboardTotals.empty(),
//       countries: const [],
//       roles: const [],
//       operationalCountries: const [],
//       supportedCurrencies: const [],
//     );
//   }

//   bool get isEmpty {
//     return summary.totalUsers == 0 &&
//         countries.isEmpty &&
//         roles.isEmpty &&
//         operationalCountries.isEmpty &&
//         supportedCurrencies.isEmpty;
//   }

//   bool get isNotEmpty => !isEmpty;

//   int get totalUsers => summary.totalUsers;

//   int get totalCreditAgents => summary.creditAgents;

//   int get totalCountries => operationalCountries.length;

//   int get totalActiveCountries {
//     return operationalCountries.where((country) => country.isActive).length;
//   }

//   /// Roles sorted alphabetically.
//   ///
//   /// Uses the UserRole model returned by the backend rather
//   /// than a hardcoded frontend role list.
//   List<UserRole> get sortedRoles {
//     final result = [...roles]
//       ..sort((first, second) => first.name.compareTo(second.name));

//     return List.unmodifiable(result);
//   }

//   /// Whether the backend has this role configured.
//   bool hasRole(String role) {
//     return roles.containsRole(role);
//   }

//   /// Returns a backend role by name.
//   UserRole? getRole(String role) {
//     return roles.getByName(role);
//   }

//   /// Returns the number of users belonging to a role.
//   ///
//   /// The role does not have to exist in a frontend enum.
//   int roleCount(String role) {
//     return summary.roleCount(role);
//   }

//   /// Role counts ordered using the backend role list.
//   ///
//   /// A role configured in the backend is included even when
//   /// its count is zero or missing from roleCounts.
//   Map<String, int> get roleCounts {
//     final result = <String, int>{};

//     for (final role in roles) {
//       result[role.name] = summary.roleCount(role.name);
//     }

//     return Map.unmodifiable(result);
//   }

//   List<AdminCountrySummary> get sortedCountries {
//     final result = [
//       ...countries,
//     ]..sort((first, second) => first.countryCode.compareTo(second.countryCode));

//     return List.unmodifiable(result);
//   }

//   List<AdminCountrySummary> get countriesByUserCount {
//     final result = [...countries]
//       ..sort((first, second) => second.totalUsers.compareTo(first.totalUsers));

//     return List.unmodifiable(result);
//   }

//   List<OperationalCountry> get sortedOperationalCountries {
//     final result = [...operationalCountries]
//       ..sort((first, second) => first.name.compareTo(second.name));

//     return List.unmodifiable(result);
//   }

//   List<OperationalCountry> get activeOperationalCountries {
//     final result =
//         operationalCountries.where((country) => country.isActive).toList()
//           ..sort((first, second) => first.name.compareTo(second.name));

//     return List.unmodifiable(result);
//   }

//   AdminCountrySummary? countrySummary(String countryCode) {
//     final normalized = countryCode.trim().toLowerCase();

//     for (final country in countries) {
//       if (country.countryCode == normalized) {
//         return country;
//       }
//     }

//     return null;
//   }

//   OperationalCountry? operationalCountry(String countryCode) {
//     return operationalCountries.getByCode(countryCode);
//   }

//   bool hasCountry(String countryCode) {
//     return operationalCountry(countryCode) != null;
//   }

//   static List<T> _parseList<T>(
//     dynamic value,
//     T Function(Map<String, dynamic>) parser,
//   ) {
//     if (value is! List) {
//       return const [];
//     }

//     return value
//         .whereType<Map>()
//         .map((item) => parser(Map<String, dynamic>.from(item)))
//         .toList();
//   }

//   static Map<String, dynamic> _asMap(dynamic value) {
//     if (value is Map) {
//       return Map<String, dynamic>.from(value);
//     }

//     return const {};
//   }

//   static List<UserRole> _parseRoles(dynamic value) {
//     if (value is! List) {
//       return const [];
//     }

//     return value.whereType<String>().map(UserRole.fromString).toList();
//   }
// }

// class AdminDashboardTotals {
//   AdminDashboardTotals({
//     required this.totalUsers,
//     required this.creditAgents,
//     required Map<String, int> roleCounts,
//   }) : roleCounts = Map.unmodifiable(roleCounts);

//   const AdminDashboardTotals.empty()
//     : totalUsers = 0,
//       creditAgents = 0,
//       roleCounts = const {};

//   final int totalUsers;

//   final int creditAgents;

//   /// Dynamic role counts returned by the backend.
//   ///
//   /// No role names are hardcoded here because backend roles
//   /// can be added or removed independently of the app.
//   final Map<String, int> roleCounts;

//   factory AdminDashboardTotals.fromJson(Map<String, dynamic> json) {
//     return AdminDashboardTotals(
//       totalUsers: NumberConversionService.toInt(json['totalUsers']),
//       creditAgents: NumberConversionService.toInt(json['creditAgents']),
//       roleCounts: _parseRoleCounts(json['roleCounts']),
//     );
//   }

//   int roleCount(String role) {
//     return roleCounts[role.trim().toLowerCase()] ?? 0;
//   }

//   bool containsRole(String role) {
//     return roleCounts.containsKey(role.trim().toLowerCase());
//   }

//   int get totalUsersFromRoles {
//     return roleCounts.values.fold(0, (total, count) => total + count);
//   }

//   bool get roleTotalsMatch {
//     return totalUsersFromRoles == totalUsers;
//   }

//   bool get hasUsers => totalUsers > 0;

//   bool get hasCreditAgents => creditAgents > 0;

//   /// Role counts sorted alphabetically by role.
//   Map<String, int> get sortedRoleCounts {
//     final entries = roleCounts.entries.toList()
//       ..sort((first, second) => first.key.compareTo(second.key));

//     return Map.unmodifiable(Map<String, int>.fromEntries(entries));
//   }

//   /// Role counts sorted from highest user count to lowest.
//   Map<String, int> get roleCountsByUserCount {
//     final entries = roleCounts.entries.toList()
//       ..sort((first, second) {
//         final countComparison = second.value.compareTo(first.value);

//         if (countComparison != 0) {
//           return countComparison;
//         }

//         return first.key.compareTo(second.key);
//       });

//     return Map.unmodifiable(Map<String, int>.fromEntries(entries));
//   }

//   /// Roles that currently contain at least one user.
//   Map<String, int> get nonZeroRoleCounts {
//     return Map.unmodifiable(
//       Map<String, int>.fromEntries(
//         roleCounts.entries.where((entry) => entry.value > 0),
//       ),
//     );
//   }

//   static Map<String, int> _parseRoleCounts(dynamic value) {
//     if (value is! Map) {
//       return const {};
//     }

//     final result = <String, int>{};

//     for (final entry in value.entries) {
//       final role = entry.key.toString().trim().toLowerCase();

//       if (role.isEmpty) {
//         continue;
//       }

//       result[role] = NumberConversionService.toInt(entry.value);
//     }

//     return result;
//   }
// }

// class AdminCountrySummary {
//   const AdminCountrySummary({required this.countryCode, required this.totals});

//   final String countryCode;

//   final AdminDashboardTotals totals;

//   factory AdminCountrySummary.fromJson(Map<String, dynamic> json) {
//     return AdminCountrySummary(
//       countryCode: (json['countryCode'] ?? '').toString().trim().toLowerCase(),
//       totals: AdminDashboardTotals.fromJson(json),
//     );
//   }

//   int get totalUsers => totals.totalUsers;

//   int get creditAgents => totals.creditAgents;

//   Map<String, int> get roleCounts {
//     return totals.roleCounts;
//   }

//   int roleCount(String role) {
//     return totals.roleCount(role);
//   }

//   bool hasRole(String role) {
//     return totals.containsRole(role);
//   }

//   Map<String, int> get nonZeroRoleCounts {
//     return totals.nonZeroRoleCounts;
//   }
// }
