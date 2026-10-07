class LoanLiquidationParams {
  LoanLiquidationParams({String? startDate, this.page = 1, this.pageSize = 50})
    : startDate = startDate ?? _today();

  final String startDate;

  final int page;
  final int pageSize;

  factory LoanLiquidationParams.fromDateTime({
    DateTime? startDate,
    int page = 1,
    int pageSize = 50,
  }) {
    return LoanLiquidationParams(
      startDate: startDate == null ? null : _formatDate(startDate),
      page: page,
      pageSize: pageSize,
    );
  }

  LoanLiquidationParams copyWith({
    String? startDate,
    int? page,
    int? pageSize,
  }) {
    return LoanLiquidationParams(
      startDate: startDate ?? this.startDate,
      page: page ?? this.page,
      pageSize: pageSize ?? this.pageSize,
    );
  }

  Map<String, dynamic> toQueryParameters() {
    return {'startDate': startDate, 'page': page, 'pageSize': pageSize};
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is LoanLiquidationParams &&
            other.startDate == startDate &&
            other.page == page &&
            other.pageSize == pageSize;
  }

  @override
  int get hashCode {
    return Object.hash(startDate, page, pageSize);
  }

  static String _today() {
    return _formatDate(DateTime.now());
  }

  static String _formatDate(DateTime date) {
    return '${date.year.toString().padLeft(4, '0')}-'
        '${date.month.toString().padLeft(2, '0')}-'
        '${date.day.toString().padLeft(2, '0')}';
  }
}
