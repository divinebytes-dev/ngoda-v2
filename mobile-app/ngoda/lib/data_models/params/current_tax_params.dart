class CurrentTaxParams {
  CurrentTaxParams({
    String? currency,
    this.page = 1,
    this.pageSize = 50,
    String? asOf,
  }) : currency = _optional(currency)?.toLowerCase(),
       asOf = _optional(asOf);

  final String? currency;
  final int page;
  final int pageSize;
  final String? asOf;

  CurrentTaxParams copyWith({
    String? currency,
    int? page,
    int? pageSize,
    String? asOf,
    bool clearCurrency = false,
    bool clearAsOf = false,
  }) {
    return CurrentTaxParams(
      currency: clearCurrency ? null : currency ?? this.currency,
      page: page ?? this.page,
      pageSize: pageSize ?? this.pageSize,
      asOf: clearAsOf ? null : asOf ?? this.asOf,
    );
  }

  // Request body for the existing POST Edge function.
  Map<String, dynamic> toJson() {
    return {
      if (currency != null) 'currency_code': currency,
      'page': page,
      'page_size': pageSize,
      if (asOf != null) 'as_of': asOf,
    };
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is CurrentTaxParams &&
            other.currency == currency &&
            other.page == page &&
            other.pageSize == pageSize &&
            other.asOf == asOf;
  }

  @override
  int get hashCode => Object.hash(currency, page, pageSize, asOf);

  static String? _optional(String? value) {
    final normalized = value?.trim();
    return normalized == null || normalized.isEmpty ? null : normalized;
  }
}
