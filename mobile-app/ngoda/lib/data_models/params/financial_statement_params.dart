class FinancialStatementParams {
  FinancialStatementParams({
    String? startDate,
    String? endDate,
    String? currency,
    this.gl,
    this.page = 1,
    this.pageSize = 50,
  }) : startDate = startDate ?? _startOfYear(),
       endDate = endDate ?? _today(),
       currency = currency == null ? null : _normalizeCurrency(currency);

  final String startDate;
  final String endDate;

  final String? currency;

  /// Optional GL account for drilldown.
  final String? gl;

  final int page;
  final int pageSize;

  factory FinancialStatementParams.fromDateTime({
    DateTime? startDate,
    DateTime? endDate,
    String? currency,
    String? gl,
    int page = 1,
    int pageSize = 50,
  }) {
    return FinancialStatementParams(
      startDate: startDate == null ? null : _formatDate(startDate),
      endDate: endDate == null ? null : _formatDate(endDate),
      currency: currency,
      gl: gl,
      page: page,
      pageSize: pageSize,
    );
  }

  FinancialStatementParams copyWith({
    String? startDate,
    String? endDate,
    String? currency,
    String? gl,
    int? page,
    int? pageSize,
    bool clearCurrency = false,
    bool clearGl = false,
    bool resetDates = false,
  }) {
    return FinancialStatementParams(
      startDate: resetDates ? _startOfYear() : startDate ?? this.startDate,
      endDate: resetDates ? _today() : endDate ?? this.endDate,
      currency: clearCurrency ? null : currency ?? this.currency,
      gl: clearGl ? null : gl ?? this.gl,
      page: page ?? this.page,
      pageSize: pageSize ?? this.pageSize,
    );
  }

  Map<String, dynamic> toQueryParameters() {
    return {
      'startDate': startDate,
      'endDate': endDate,
      if (currency != null && currency!.isNotEmpty) 'currency': currency,
      if (gl != null && gl!.trim().isNotEmpty) 'gl': gl,
      'page': page,
      'pageSize': pageSize,
    };
  }

  Map<String, dynamic> toStatementQueryParameters() {
    return {'startDate': startDate, 'endDate': endDate};
  }

  Map<String, dynamic> toDrilldownQueryParameters() {
    return {
      'startDate': startDate,
      'endDate': endDate,
      if (currency != null && currency!.isNotEmpty) 'currency': currency,
      if (gl != null && gl!.trim().isNotEmpty) 'gl': gl,
      'page': page,
      'pageSize': pageSize,
    };
  }

  Map<String, dynamic> toRecentTransactionQueryParameters() {
    return {
      'startDate': startDate,
      'endDate': endDate,
      if (currency != null && currency!.isNotEmpty) 'currency': currency,
      'page': page,
      'pageSize': pageSize,
    };
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is FinancialStatementParams &&
            other.startDate == startDate &&
            other.endDate == endDate &&
            other.currency == currency &&
            other.gl == gl &&
            other.page == page &&
            other.pageSize == pageSize;
  }

  @override
  int get hashCode {
    return Object.hash(startDate, endDate, currency, gl, page, pageSize);
  }

  static String _startOfYear() {
    final now = DateTime.now();

    return _formatDate(DateTime(now.year, 1, 1));
  }

  static String _today() {
    return _formatDate(DateTime.now());
  }

  static String _formatDate(DateTime date) {
    return '${date.year.toString().padLeft(4, '0')}-'
        '${date.month.toString().padLeft(2, '0')}-'
        '${date.day.toString().padLeft(2, '0')}';
  }

  static String _normalizeCurrency(String value) {
    return value.trim().toLowerCase();
  }
}
