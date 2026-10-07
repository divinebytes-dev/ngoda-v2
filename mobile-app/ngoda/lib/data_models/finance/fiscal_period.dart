class FiscalPeriod {
  final String id;
  final int fiscalYear;
  final int period;
  final String countryCode;
  final String periodName;
  final DateTime openingDate;
  final DateTime closingDate;
  final bool isClosed;
  final DateTime createdAt;
  final String createdBy;
  final DateTime updatedAt;
  final String? updatedBy;

  const FiscalPeriod({
    required this.id,
    required this.fiscalYear,
    required this.period,
    required this.countryCode,
    required this.periodName,
    required this.openingDate,
    required this.closingDate,
    required this.isClosed,
    required this.createdAt,
    required this.createdBy,
    required this.updatedAt,
    this.updatedBy,
  });

  factory FiscalPeriod.fromJson(Map<String, dynamic> json) {
    return FiscalPeriod(
      id: json['id'] as String,
      fiscalYear: (json['fiscal_year'] as num).toInt(),
      period: (json['period'] as num).toInt(),
      countryCode: json['country_code'] as String,
      periodName: json['period_name'] as String,
      openingDate: DateTime.parse(json['opening_date'] as String),
      closingDate: DateTime.parse(json['closing_date'] as String),
      isClosed: json['is_closed'] as bool,
      createdAt: DateTime.parse(json['created_at'] as String),
      createdBy: json['created_by'] as String,
      updatedAt: DateTime.parse(json['updated_at'] as String),
      updatedBy: json['updated_by'] as String?,
    );
  }
}
