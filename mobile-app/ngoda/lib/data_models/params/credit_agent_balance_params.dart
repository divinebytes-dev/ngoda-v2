class CreditAgentBalanceParams {
  CreditAgentBalanceParams({
    this.merchantId,
    this.page = 1,
    this.pageSize = 50,
    String? currency,
  }) : currency = currency == null ? null : _normalizeCurrency(currency);

  final String? merchantId;
  final int page;
  final int pageSize;
  final String? currency;

  CreditAgentBalanceParams copyWith({
    String? merchantId,
    int? page,
    int? pageSize,
    String? currency,
    bool clearMerchantId = false,
    bool clearCurrency = false,
  }) {
    return CreditAgentBalanceParams(
      merchantId: clearMerchantId ? null : merchantId ?? this.merchantId,
      page: page ?? this.page,
      pageSize: pageSize ?? this.pageSize,
      currency: clearCurrency ? null : currency ?? this.currency,
    );
  }

  Map<String, dynamic> toQueryParameters() {
    return {
      if (merchantId != null && merchantId!.trim().isNotEmpty)
        'merchantId': merchantId,
      if (currency != null && currency!.isNotEmpty) 'currency': currency,
      'page': page,
      'pageSize': pageSize,
    };
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is CreditAgentBalanceParams &&
            other.merchantId == merchantId &&
            other.page == page &&
            other.pageSize == pageSize &&
            other.currency == currency;
  }

  @override
  int get hashCode {
    return Object.hash(merchantId, page, pageSize, currency);
  }

  static String _normalizeCurrency(String value) {
    return value.trim().toLowerCase();
  }
}
