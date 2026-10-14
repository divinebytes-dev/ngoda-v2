class LoanDetailsParams {
  LoanDetailsParams({required String loanId, this.page = 1, this.pageSize = 50})
    : loanId = loanId.trim() {
    if (this.loanId.isEmpty) {
      throw ArgumentError.value(loanId, 'loanId', 'Loan ID cannot be empty.');
    }

    if (page < 1) {
      throw ArgumentError.value(
        page,
        'page',
        'Page must be greater than zero.',
      );
    }

    if (pageSize < 1) {
      throw ArgumentError.value(
        pageSize,
        'pageSize',
        'Page size must be greater than zero.',
      );
    }
  }

  final String loanId;
  final int page;
  final int pageSize;

  LoanDetailsParams copyWith({String? loanId, int? page, int? pageSize}) {
    return LoanDetailsParams(
      loanId: loanId ?? this.loanId,
      page: page ?? this.page,
      pageSize: pageSize ?? this.pageSize,
    );
  }

  Map<String, dynamic> toQueryParameters() {
    return {'loan_id': loanId, 'page': page, 'page_size': pageSize};
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is LoanDetailsParams &&
            other.loanId == loanId &&
            other.page == page &&
            other.pageSize == pageSize;
  }

  @override
  int get hashCode => Object.hash(loanId, page, pageSize);
}
