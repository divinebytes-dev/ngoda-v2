import 'financial_badge.dart';

class FinancialBadgeList {
  final List<FinancialBadge> badges;

  const FinancialBadgeList({required this.badges});

  factory FinancialBadgeList.fromJson(Map<String, dynamic> json) {
    final rawBadges = json['badges'];
    if (rawBadges is! List) return FinancialBadgeList.empty;

    return FinancialBadgeList(
      badges: rawBadges
          .whereType<Map>()
          .map(
            (item) => FinancialBadge.fromJson(Map<String, dynamic>.from(item)),
          )
          .toList(growable: false),
    );
  }

  Map<String, dynamic> toJson() => {
    'badges': badges.map((badge) => badge.toJson()).toList(growable: false),
  };

  FinancialBadgeList copyWith({List<FinancialBadge>? badges}) {
    return FinancialBadgeList(badges: badges ?? this.badges);
  }

  static const empty = FinancialBadgeList(badges: []);
}

extension FinancialBadgeListX on FinancialBadgeList {
  bool get isEmpty => badges.isEmpty;
  bool get isNotEmpty => badges.isNotEmpty;
  int get totalCount => badges.length;
  int get earnedCount => badges.where((badge) => badge.earned).length;
  int get lockedCount => totalCount - earnedCount;

  double get completionRatio => totalCount == 0 ? 0 : earnedCount / totalCount;
  double get completionPercent => completionRatio * 100;

  List<FinancialBadge> get earnedBadges {
    final result = badges.where((badge) => badge.earned).toList();
    result.sort(_earnedSort);
    return result;
  }

  List<FinancialBadge> get lockedBadges {
    final result = badges.where((badge) => badge.locked).toList();
    result.sort(_badgeSort);
    return result;
  }

  List<FinancialBadge> get sortedBadges {
    final result = [...badges];
    result.sort(_badgeSort);
    return result;
  }

  List<String> get behaviorCodes {
    final result = badges
        .map((badge) => badge.behaviorCode)
        .where((value) => value.isNotEmpty)
        .toSet()
        .toList();
    result.sort((a, b) => _behaviorOrder(a).compareTo(_behaviorOrder(b)));
    return result;
  }

  List<String> get metricCodes {
    final result = badges
        .map((badge) => badge.metricCode)
        .where((value) => value.isNotEmpty)
        .toSet()
        .toList();
    result.sort();
    return result;
  }

  Map<String, List<FinancialBadge>> get byBehavior => {
    for (final behavior in behaviorCodes) behavior: badgesForBehavior(behavior),
  };

  Map<String, List<FinancialBadge>> get byMetric => {
    for (final metric in metricCodes) metric: badgesForMetric(metric),
  };

  List<FinancialBadge> badgesForBehavior(String behavior) {
    final key = behavior.toLowerCase();
    final result = badges.where((badge) => badge.behaviorCode == key).toList();
    result.sort(_badgeSort);
    return result;
  }

  List<FinancialBadge> badgesForMetric(String metric) {
    final key = metric.toLowerCase();
    final result = badges.where((badge) => badge.metricCode == key).toList();
    result.sort(_badgeSort);
    return result;
  }

  FinancialBadge? getById(String id) {
    for (final badge in badges) {
      if (badge.id == id) return badge;
    }
    return null;
  }

  FinancialBadge? getByCode(String code) {
    final key = code.toLowerCase();
    for (final badge in badges) {
      if (badge.code.toLowerCase() == key) return badge;
    }
    return null;
  }

  FinancialBadge? highestEarnedForBehavior(String behavior) {
    final values = badgesForBehavior(
      behavior,
    ).where((badge) => badge.earned).toList();
    if (values.isEmpty) return null;
    values.sort((a, b) => b.level.compareTo(a.level));
    return values.first;
  }

  FinancialBadge? nextBadgeForBehavior(String behavior) {
    final values = badgesForBehavior(
      behavior,
    ).where((badge) => badge.locked).toList();
    if (values.isEmpty) return null;
    values.sort((a, b) => a.level.compareTo(b.level));
    return values.first;
  }

  FinancialBadge? highestEarnedForMetric(String metric) {
    final values = badgesForMetric(
      metric,
    ).where((badge) => badge.earned).toList();
    if (values.isEmpty) return null;
    values.sort((a, b) => b.level.compareTo(a.level));
    return values.first;
  }

  FinancialBadge? nextBadgeForMetric(String metric) {
    final values = badgesForMetric(
      metric,
    ).where((badge) => badge.locked).toList();
    if (values.isEmpty) return null;
    values.sort((a, b) => a.level.compareTo(b.level));
    return values.first;
  }

  int earnedCountForBehavior(String behavior) =>
      badgesForBehavior(behavior).where((badge) => badge.earned).length;

  int totalCountForBehavior(String behavior) =>
      badgesForBehavior(behavior).length;

  double completionForBehavior(String behavior) {
    final values = badgesForBehavior(behavior);
    if (values.isEmpty) return 0;
    return values.where((badge) => badge.earned).length / values.length;
  }

  static int _badgeSort(FinancialBadge a, FinancialBadge b) {
    final behaviorCompare = _behaviorOrder(
      a.behaviorCode,
    ).compareTo(_behaviorOrder(b.behaviorCode));
    if (behaviorCompare != 0) return behaviorCompare;

    final metricCompare = a.metricCode.compareTo(b.metricCode);
    if (metricCompare != 0) return metricCompare;

    return a.level.compareTo(b.level);
  }

  static int _earnedSort(FinancialBadge a, FinancialBadge b) {
    final aDate = a.achievedAt;
    final bDate = b.achievedAt;

    if (aDate != null && bDate != null) {
      final result = bDate.compareTo(aDate);
      if (result != 0) return result;
    } else if (aDate != null) {
      return -1;
    } else if (bDate != null) {
      return 1;
    }

    return _badgeSort(a, b);
  }

  static int _behaviorOrder(String behavior) {
    switch (behavior.toLowerCase()) {
      case 'saver':
        return 0;
      case 'investor':
        return 1;
      case 'shopper':
        return 2;
      case 'borrower':
        return 3;
      default:
        return 99;
    }
  }
}
