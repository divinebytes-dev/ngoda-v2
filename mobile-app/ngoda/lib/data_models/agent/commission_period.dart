import 'package:ngoda/data_models/agent/commission_stats.dart';

class CommissionPeriod {
  const CommissionPeriod({
    required this.today,
    required this.week,
    required this.fortnight,
    required this.month,
    required this.year,
  });

  final CommissionStats today;
  final CommissionStats week;
  final CommissionStats fortnight;
  final CommissionStats month;
  final CommissionStats year;

  factory CommissionPeriod.fromJson(Map<String, dynamic> json) {
    return CommissionPeriod(
      today: CommissionStats.fromJson(_asMap(json['today'])),
      week: CommissionStats.fromJson(_asMap(json['week'])),
      fortnight: CommissionStats.fromJson(_asMap(json['fortnight'])),
      month: CommissionStats.fromJson(_asMap(json['month'])),
      year: CommissionStats.fromJson(_asMap(json['year'])),
    );
  }

  static Map<String, dynamic> _asMap(dynamic value) {
    if (value is Map) {
      return Map<String, dynamic>.from(value);
    }

    return const {};
  }
}
