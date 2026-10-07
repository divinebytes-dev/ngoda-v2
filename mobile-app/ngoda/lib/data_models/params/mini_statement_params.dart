class MiniStatementParams {
  MiniStatementParams({
    String? currency,
    String? startDate,
    String? endDate,
    this.page = 1,
    this.pageSize = 50,
  }) : currency = currency == null ? null : _normalizeCurrency(currency),
       startDate = startDate ?? _startOfYear(),
       endDate = endDate ?? _today();

  final String? currency;

  final String startDate;
  final String endDate;

  final int page;
  final int pageSize;

  MiniStatementParams copyWith({
    String? currency,
    String? startDate,
    String? endDate,
    int? page,
    int? pageSize,
    bool clearCurrency = false,
    bool resetDates = false,
  }) {
    return MiniStatementParams(
      currency: clearCurrency ? null : currency ?? this.currency,
      startDate: resetDates ? _startOfYear() : startDate ?? this.startDate,
      endDate: resetDates ? _today() : endDate ?? this.endDate,
      page: page ?? this.page,
      pageSize: pageSize ?? this.pageSize,
    );
  }

  Map<String, dynamic> toQueryParameters() {
    return {
      if (currency != null && currency!.isNotEmpty) 'currency': currency,
      'startDate': startDate,
      'endDate': endDate,
      'page': page,
      'pageSize': pageSize,
    };
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is MiniStatementParams &&
            other.currency == currency &&
            other.startDate == startDate &&
            other.endDate == endDate &&
            other.page == page &&
            other.pageSize == pageSize;
  }

  @override
  int get hashCode {
    return Object.hash(currency, startDate, endDate, page, pageSize);
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
