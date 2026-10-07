class GlEntryParams {
  GlEntryParams({
    required String gl,
    required String currency,
    required this.fiscalYear,
    required this.period,
    this.page = 1,
    this.pageSize = 50,
  }) : gl = gl.trim(),
       currency = currency.trim().toLowerCase();

  final String gl;
  final String currency;

  final int fiscalYear;
  final int period;

  final int page;
  final int pageSize;

  GlEntryParams copyWith({
    String? gl,
    String? currency,
    int? fiscalYear,
    int? period,
    int? page,
    int? pageSize,
  }) {
    return GlEntryParams(
      gl: gl ?? this.gl,
      currency: currency ?? this.currency,
      fiscalYear: fiscalYear ?? this.fiscalYear,
      period: period ?? this.period,
      page: page ?? this.page,
      pageSize: pageSize ?? this.pageSize,
    );
  }

  Map<String, dynamic> toQueryParameters() {
    return {
      'gl': gl,
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
        other is GlEntryParams &&
            other.gl == gl &&
            other.currency == currency &&
            other.fiscalYear == fiscalYear &&
            other.period == period &&
            other.page == page &&
            other.pageSize == pageSize;
  }

  @override
  int get hashCode {
    return Object.hash(gl, currency, fiscalYear, period, page, pageSize);
  }
}
