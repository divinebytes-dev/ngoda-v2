class BlockchainTransactionParams {
  const BlockchainTransactionParams({this.page = 1, this.pageSize = 50});

  final int page;
  final int pageSize;

  BlockchainTransactionParams copyWith({int? page, int? pageSize}) {
    return BlockchainTransactionParams(
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
        other is BlockchainTransactionParams &&
            other.page == page &&
            other.pageSize == pageSize;
  }

  @override
  int get hashCode {
    return Object.hash(page, pageSize);
  }
}
