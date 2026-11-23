class ReserveBankTaxSummary {
  ReserveBankTaxSummary({
    required this.fiscalYear,
    required this.totalUsd,
    required List<ReserveBankTaxCurrencySummary> currencies,
  }) : currencies = List.unmodifiable(currencies);

  final int fiscalYear;
  final String? totalUsd;
  final List<ReserveBankTaxCurrencySummary> currencies;

  factory ReserveBankTaxSummary.fromJson(Map<String, dynamic> json) {
    return ReserveBankTaxSummary(
      fiscalYear: json['fiscal_year'] as int,
      totalUsd: json['total_usd']?.toString(),
      currencies: (json['currency_breakdown'] as List)
          .map(
            (row) => ReserveBankTaxCurrencySummary.fromJson(
              Map<String, dynamic>.from(row as Map),
            ),
          )
          .toList(growable: false),
    );
  }
}

class ReserveBankTaxCurrencySummary {
  const ReserveBankTaxCurrencySummary({
    required this.currency,
    required this.taxAmount,
    required this.usdValue,
  });

  final String currency;
  final String taxAmount;
  final String? usdValue;

  factory ReserveBankTaxCurrencySummary.fromJson(Map<String, dynamic> json) {
    return ReserveBankTaxCurrencySummary(
      currency: (json['currency'] as String).toLowerCase(),
      taxAmount: (json['tax_amount'] as Object).toString(),
      usdValue: json['usd_value']?.toString(),
    );
  }
}
