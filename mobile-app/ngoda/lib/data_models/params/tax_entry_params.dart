class TaxEntryParams {
  TaxEntryParams({
    required String currency,
    required this.fiscalYear,
    required this.period,
    this.page = 1,
    this.pageSize = 50,
  }) : currency = currency.trim().toLowerCase();

  final String currency;

  final int fiscalYear;
  final int period;

  final int page;
  final int pageSize;

  TaxEntryParams copyWith({
    String? currency,
    int? fiscalYear,
    int? period,
    int? page,
    int? pageSize,
  }) {
    return TaxEntryParams(
      currency: currency ?? this.currency,
      fiscalYear: fiscalYear ?? this.fiscalYear,
      period: period ?? this.period,
      page: page ?? this.page,
      pageSize: pageSize ?? this.pageSize,
    );
  }

  Map<String, dynamic> toQueryParameters() {
    return {
      'currency': currency,
      'fiscalYear': fiscalYear,
      'period': period,
      'page': page,
      'pageSize': pageSize,
    };
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is TaxEntryParams &&
            other.currency == currency &&
            other.fiscalYear == fiscalYear &&
            other.period == period &&
            other.page == page &&
            other.pageSize == pageSize;
  }

  @override
  int get hashCode {
    return Object.hash(currency, fiscalYear, period, page, pageSize);
  }
}
