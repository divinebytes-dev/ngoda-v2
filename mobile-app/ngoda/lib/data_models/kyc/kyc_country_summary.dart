import 'package:ngoda/data_models/kyc/kyc_role_summary.dart';
import 'package:ngoda/data_models/kyc/kyc_stats.dart';

class KycCountrySummary {
  KycCountrySummary({
    required this.countryCode,
    required this.countryName,
    required this.stats,
    required Map<String, KycRoleSummary> roleCounts,
  }) : roleCounts = Map.unmodifiable(roleCounts);

  final String countryCode;

  final String countryName;

  final KycStats stats;

  /// Dynamic backend roles.
  final Map<String, KycRoleSummary> roleCounts;

  factory KycCountrySummary.fromJson(Map<String, dynamic> json) {
    return KycCountrySummary(
      countryCode: json['country_code']?.toString().trim().toLowerCase() ?? '',
      countryName: json['country_name']?.toString().trim() ?? '',
      stats: KycStats.fromJson(json),
      roleCounts: _parseRoleCounts(json['role_counts']),
    );
  }

  int get totalUsers => stats.totalUsers;

  int get started => stats.started;

  int get notStarted => stats.notStarted;

  int get verified => stats.verified;

  int get pendingReview => stats.pendingReview;

  double get startedPercentage => stats.startedPercentage;

  double get notStartedPercentage => stats.notStartedPercentage;

  double get verifiedPercentage => stats.verifiedPercentage;

  double get pendingReviewPercentage => stats.pendingReviewPercentage;

  bool get hasPendingReviews => stats.hasPendingReviews;

  KycRoleSummary? roleSummary(String role) {
    return roleCounts[role.trim().toLowerCase()];
  }

  List<MapEntry<String, KycRoleSummary>> get sortedRoleCounts {
    final entries = roleCounts.entries.toList()
      ..sort(
        (first, second) =>
            second.value.totalUsers.compareTo(first.value.totalUsers),
      );

    return List.unmodifiable(entries);
  }

  static Map<String, KycRoleSummary> _parseRoleCounts(dynamic value) {
    if (value is! Map) {
      return const {};
    }

    final result = <String, KycRoleSummary>{};

    for (final entry in value.entries) {
      if (entry.value is! Map) {
        continue;
      }

      final role = entry.key.toString().trim().toLowerCase();

      if (role.isEmpty) {
        continue;
      }

      result[role] = KycRoleSummary.fromJson(
        Map<String, dynamic>.from(entry.value as Map),
      );
    }

    return result;
  }
}
