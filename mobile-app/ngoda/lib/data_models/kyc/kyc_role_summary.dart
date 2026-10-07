import 'package:ngoda/data_models/kyc/kyc_stats.dart';

class KycRoleSummary {
  const KycRoleSummary({required this.stats});

  final KycStats stats;

  factory KycRoleSummary.fromJson(Map<String, dynamic> json) {
    return KycRoleSummary(stats: KycStats.fromJson(json));
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
}
