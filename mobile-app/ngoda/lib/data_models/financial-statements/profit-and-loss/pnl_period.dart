class PnLPeriod {
  const PnLPeriod({required this.startDate, required this.endDate});

  final DateTime startDate;
  final DateTime endDate;

  factory PnLPeriod.fromJson(Map<String, dynamic> json) {
    return PnLPeriod(
      startDate: _parseRequiredDate(json['startDate'], 'startDate'),
      endDate: _parseRequiredDate(json['endDate'], 'endDate'),
    );
  }

  static DateTime _parseRequiredDate(dynamic value, String field) {
    final raw = value?.toString().trim();

    if (raw == null || raw.isEmpty) {
      throw FormatException('PnLPeriod.$field is required.');
    }

    return DateTime.parse(raw);
  }
}
