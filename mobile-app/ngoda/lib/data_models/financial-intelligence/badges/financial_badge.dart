class FinancialBadge {
  final String id;
  final String code;
  final String behavior;
  final String metric;
  final int level;
  final double thresholdUsd;
  final String name;
  final String? description;
  final bool earned;
  final double? achievedValueUsd;
  final int? fiscalYear;
  final int? period;
  final DateTime? achievedAt;

  const FinancialBadge({
    required this.id,
    required this.code,
    required this.behavior,
    required this.metric,
    required this.level,
    required this.thresholdUsd,
    required this.name,
    required this.description,
    required this.earned,
    required this.achievedValueUsd,
    required this.fiscalYear,
    required this.period,
    required this.achievedAt,
  });

  factory FinancialBadge.fromJson(Map<String, dynamic> json) {
    return FinancialBadge(
      id: json['id']?.toString() ?? '',
      code: json['code']?.toString() ?? '',
      behavior: json['behavior']?.toString().toLowerCase() ?? '',
      metric: json['metric']?.toString().toLowerCase() ?? '',
      level: _toInt(json['level']) ?? 0,
      thresholdUsd: _toDouble(json['threshold_usd']) ?? 0,
      name: json['name']?.toString() ?? '',
      description: json['description']?.toString(),
      earned: json['earned'] == true,
      achievedValueUsd: _toDouble(json['achieved_value_usd']),
      fiscalYear: _toInt(json['fiscal_year']),
      period: _toInt(json['period']),
      achievedAt: _toDateTime(json['achieved_at']),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'code': code,
    'behavior': behavior,
    'metric': metric,
    'level': level,
    'threshold_usd': thresholdUsd,
    'name': name,
    'description': description,
    'earned': earned,
    'achieved_value_usd': achievedValueUsd,
    'fiscal_year': fiscalYear,
    'period': period,
    'achieved_at': achievedAt?.toIso8601String(),
  };

  FinancialBadge copyWith({
    String? id,
    String? code,
    String? behavior,
    String? metric,
    int? level,
    double? thresholdUsd,
    String? name,
    String? description,
    bool? earned,
    double? achievedValueUsd,
    int? fiscalYear,
    int? period,
    DateTime? achievedAt,
  }) {
    return FinancialBadge(
      id: id ?? this.id,
      code: code ?? this.code,
      behavior: behavior ?? this.behavior,
      metric: metric ?? this.metric,
      level: level ?? this.level,
      thresholdUsd: thresholdUsd ?? this.thresholdUsd,
      name: name ?? this.name,
      description: description ?? this.description,
      earned: earned ?? this.earned,
      achievedValueUsd: achievedValueUsd ?? this.achievedValueUsd,
      fiscalYear: fiscalYear ?? this.fiscalYear,
      period: period ?? this.period,
      achievedAt: achievedAt ?? this.achievedAt,
    );
  }

  static double? _toDouble(dynamic value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString());
  }

  static int? _toInt(dynamic value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value.toString());
  }

  static DateTime? _toDateTime(dynamic value) {
    if (value == null) return null;
    final stringValue = value.toString();
    if (stringValue.isEmpty) return null;
    return DateTime.tryParse(stringValue);
  }
}

extension FinancialBadgeX on FinancialBadge {
  bool get locked => !earned;
  String get behaviorCode => behavior.toLowerCase();
  String get metricCode => metric.toLowerCase();

  String get behaviorLabel {
    switch (behaviorCode) {
      case 'shopper':
        return 'Shopper';
      case 'saver':
        return 'Saver';
      case 'investor':
        return 'Investor';
      case 'borrower':
        return 'Borrower';
      default:
        return _titleCase(behaviorCode);
    }
  }

  String get metricLabel {
    switch (metricCode) {
      case 'spending':
        return 'Spending';
      case 'saving':
      case 'savings':
        return 'Savings';
      case 'investment':
        return 'Investment';
      case 'borrowing':
        return 'Borrowing';
      default:
        return _titleCase(metricCode);
    }
  }

  String get levelLabel => 'Level $level';
  String get statusLabel => earned ? 'Earned' : 'Locked';
  bool get hasAchievementValue => achievedValueUsd != null;
  bool get hasAchievementPeriod => fiscalYear != null && period != null;

  String? get achievementPeriodLabel {
    if (!hasAchievementPeriod) return null;
    return 'FY $fiscalYear • P$period';
  }

  double? get achievementThresholdRatio {
    final achieved = achievedValueUsd;
    if (achieved == null || thresholdUsd <= 0) return null;
    return achieved / thresholdUsd;
  }

  double? get achievementThresholdPercent {
    final ratio = achievementThresholdRatio;
    return ratio == null ? null : ratio * 100;
  }

  static String _titleCase(String value) {
    if (value.isEmpty) return '';
    return value
        .split(RegExp(r'[_\-\s]+'))
        .where((part) => part.isNotEmpty)
        .map(
          (part) =>
              '${part[0].toUpperCase()}${part.substring(1).toLowerCase()}',
        )
        .join(' ');
  }
}
