class ReserveBankDashboard {
  ReserveBankDashboard({
    required this.totalUsd,
    required List<ReserveBankTaxCurrency> currencyBreakdown,
  }) : currencyBreakdown = List.unmodifiable(currencyBreakdown);

  final String? totalUsd;
  final List<ReserveBankTaxCurrency> currencyBreakdown;

  factory ReserveBankDashboard.fromJson(Map<String, dynamic> json) {
    final rows = json['currency_breakdown'] as List<dynamic>;

    return ReserveBankDashboard(
      totalUsd: json['total_usd'] as String?,
      currencyBreakdown: rows
          .map(
            (row) =>
                ReserveBankTaxCurrency.fromJson(row as Map<String, dynamic>),
          )
          .toList(growable: false),
    );
  }
}

class ReserveBankTaxCurrency {
  const ReserveBankTaxCurrency({
    required this.currency,
    required this.tax,
    required this.usdValue,
  });

  final String currency;
  final String tax;
  final String? usdValue;

  factory ReserveBankTaxCurrency.fromJson(Map<String, dynamic> json) {
    return ReserveBankTaxCurrency(
      currency: json['currency'] as String,
      tax: json['tax'] as String,
      usdValue: json['usd_value'] as String?,
    );
  }
}
