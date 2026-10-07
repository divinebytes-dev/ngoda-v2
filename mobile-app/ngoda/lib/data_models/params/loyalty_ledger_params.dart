class LoyaltyLedgerParams {
  const LoyaltyLedgerParams({this.page = 1, this.pageSize = 50});

  final int page;
  final int pageSize;

  LoyaltyLedgerParams copyWith({int? page, int? pageSize}) {
    return LoyaltyLedgerParams(
      page: page ?? this.page,
      pageSize: pageSize ?? this.pageSize,
    );
  }

  Map<String, dynamic> toQueryParameters() {
    return {'page': page, 'page_size': pageSize};
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is LoyaltyLedgerParams &&
            other.page == page &&
            other.pageSize == pageSize;
  }

  @override
  int get hashCode => Object.hash(page, pageSize);
}
