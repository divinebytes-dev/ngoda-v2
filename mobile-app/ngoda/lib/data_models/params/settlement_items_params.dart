class SettlementItemsParams {
  SettlementItemsParams({
    required String batchId,
    required String currency,
    this.page = 1,
    this.pageSize = 50,
  }) : batchId = batchId.trim(),
       currency = currency.trim().toLowerCase();

  final String batchId;
  final String currency;

  final int page;
  final int pageSize;

  SettlementItemsParams copyWith({
    String? batchId,
    String? currency,
    int? page,
    int? pageSize,
  }) {
    return SettlementItemsParams(
      batchId: batchId ?? this.batchId,
      currency: currency ?? this.currency,
      page: page ?? this.page,
      pageSize: pageSize ?? this.pageSize,
    );
  }

  Map<String, dynamic> toQueryParameters() {
    return {'batchId': batchId, 'page': page, 'pageSize': pageSize};
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is SettlementItemsParams &&
            other.batchId == batchId &&
            other.currency == currency &&
            other.page == page &&
            other.pageSize == pageSize;
  }

  @override
  int get hashCode {
    return Object.hash(batchId, currency, page, pageSize);
  }
}
