import 'package:ngoda/data_models/common/report_pagination.dart';
import 'package:ngoda/data_models/kyc/user_kyc_review_summary.dart';

class UserKycReviewPage {
  UserKycReviewPage({
    required this.pagination,
    required List<UserKycReviewSummary> data,
  }) : data = List.unmodifiable(data);

  final ReportPagination pagination;

  final List<UserKycReviewSummary> data;

  factory UserKycReviewPage.fromJson(Map<String, dynamic> json) {
    final rows = json['data'];

    return UserKycReviewPage(
      pagination: ReportPagination.fromJson(json),
      data: rows is List
          ? rows
                .whereType<Map>()
                .map(
                  (item) => UserKycReviewSummary.fromJson(
                    Map<String, dynamic>.from(item),
                  ),
                )
                .toList()
          : const [],
    );
  }

  bool get isEmpty => data.isEmpty;

  bool get isNotEmpty => data.isNotEmpty;

  Map<String, List<UserKycReviewSummary>> get groupedByCountry {
    final groups = <String, List<UserKycReviewSummary>>{};

    for (final user in data) {
      groups.putIfAbsent(user.countryCode, () => []).add(user);
    }

    for (final users in groups.values) {
      users.sort(_compareUsers);
    }

    return Map.unmodifiable(
      groups.map(
        (country, users) => MapEntry(country, List.unmodifiable(users)),
      ),
    );
  }

  static int _compareUsers(
    UserKycReviewSummary first,
    UserKycReviewSummary second,
  ) {
    final firstStarted = first.hasKycStarted;

    final secondStarted = second.hasKycStarted;

    if (firstStarted != secondStarted) {
      return firstStarted ? -1 : 1;
    }

    if (firstStarted && secondStarted) {
      final firstUpdated = first.kycUpdatedAt ?? first.kycStartedAt;

      final secondUpdated = second.kycUpdatedAt ?? second.kycStartedAt;

      if (firstUpdated != null && secondUpdated != null) {
        final result = secondUpdated.compareTo(firstUpdated);

        if (result != 0) {
          return result;
        }
      } else if (firstUpdated != null) {
        return -1;
      } else if (secondUpdated != null) {
        return 1;
      }
    }

    return first.fullName.toLowerCase().compareTo(
      second.fullName.toLowerCase(),
    );
  }
}
