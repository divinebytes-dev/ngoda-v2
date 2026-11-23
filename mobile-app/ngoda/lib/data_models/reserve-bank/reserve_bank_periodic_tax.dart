import 'package:ngoda/services/number_conversion_service.dart';

class ReserveBankTaxBalancePeriod {
  ReserveBankTaxBalancePeriod({
    required this.currencyCode,
    required this.fiscalYear,
    required List<ReserveBankTaxPeriodBalance> periods,
  }) : periods = List.unmodifiable(periods);

  final String currencyCode;
  final int fiscalYear;
  final List<ReserveBankTaxPeriodBalance> periods;

  factory ReserveBankTaxBalancePeriod.fromJson(Map<String, dynamic> json) {
    return ReserveBankTaxBalancePeriod(
      currencyCode:
          json['currency_code']?.toString().trim().toLowerCase() ?? '',
      fiscalYear: NumberConversionService.toInt(
        json['fiscalYear'] ?? json['fiscal_year'],
      ),
      periods: _parsePeriods(json['periods']),
    );
  }

  bool get isEmpty => periods.isEmpty;

  bool get isNotEmpty => periods.isNotEmpty;

  double get totalGrossAmount =>
      periods.fold(0.0, (total, period) => total + period.grossAmount);

  double get totalTaxAmount =>
      periods.fold(0.0, (total, period) => total + period.taxAmount);

  static List<ReserveBankTaxPeriodBalance> _parsePeriods(dynamic value) {
    if (value is! List) {
      return const [];
    }

    return value
        .whereType<Map>()
        .map(
          (period) => ReserveBankTaxPeriodBalance.fromJson(
            Map<String, dynamic>.from(period),
          ),
        )
        .toList();
  }
}

class ReserveBankTaxPeriodBalance {
  const ReserveBankTaxPeriodBalance({
    required this.period,
    required this.grossAmount,
    required this.taxAmount,
    required this.taxRate,
  });

  final int period;
  final double grossAmount;
  final double taxAmount;
  final double? taxRate;

  factory ReserveBankTaxPeriodBalance.fromJson(Map<String, dynamic> json) {
    final taxRate = json['tax_rate'];

    return ReserveBankTaxPeriodBalance(
      period: NumberConversionService.toInt(json['period']),
      grossAmount: NumberConversionService.toDouble(json['gross_amount']),
      taxAmount: NumberConversionService.toDouble(json['tax_amount']),
      taxRate: taxRate == null
          ? null
          : NumberConversionService.toDouble(taxRate),
    );
  }
}
