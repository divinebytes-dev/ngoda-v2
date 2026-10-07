import 'package:ngoda/services/number_conversion_service.dart';

class KycStats {
  const KycStats({
    required this.totalUsers,
    required this.started,
    required this.notStarted,
    required this.verified,
    required this.pendingReview,
  });

  const KycStats.empty()
    : totalUsers = 0,
      started = 0,
      notStarted = 0,
      verified = 0,
      pendingReview = 0;

  final int totalUsers;

  final int started;

  final int notStarted;

  final int verified;

  final int pendingReview;

  factory KycStats.fromJson(Map<String, dynamic> json) {
    return KycStats(
      totalUsers: NumberConversionService.toInt(json['total_users']),
      started: NumberConversionService.toInt(json['started']),
      notStarted: NumberConversionService.toInt(json['not_started']),
      verified: NumberConversionService.toInt(json['verified']),
      pendingReview: NumberConversionService.toInt(json['pending_review']),
    );
  }

  double get startedPercentage => _percentage(started);

  double get notStartedPercentage => _percentage(notStarted);

  double get verifiedPercentage => _percentage(verified);

  double get pendingReviewPercentage => _percentage(pendingReview);

  bool get hasUsers => totalUsers > 0;

  bool get hasPendingReviews => pendingReview > 0;

  double _percentage(int value) {
    if (totalUsers == 0) {
      return 0;
    }

    return (value / totalUsers) * 100;
  }
}
