class WalletEntryParams {
  WalletEntryParams({
    required String currency,
    required String walletOwner,
    required this.fiscalYear,
    required this.period,
    this.page = 1,
    this.pageSize = 50,
  }) : currency = currency.trim().toLowerCase(),
       walletOwner = walletOwner.trim().toLowerCase();

  final String currency;
  final String walletOwner;

  final int fiscalYear;
  final int period;

  final int page;
  final int pageSize;

  WalletEntryParams copyWith({
    String? currency,
    String? walletOwner,
    int? fiscalYear,
    int? period,
    int? page,
    int? pageSize,
  }) {
    return WalletEntryParams(
      currency: currency ?? this.currency,
      walletOwner: walletOwner ?? this.walletOwner,
      fiscalYear: fiscalYear ?? this.fiscalYear,
      period: period ?? this.period,
      page: page ?? this.page,
      pageSize: pageSize ?? this.pageSize,
    );
  }

  Map<String, dynamic> toQueryParameters() {
    return {
      'currency': currency,
      'walletOwner': walletOwner,
      'fiscalYear': fiscalYear,
      'period': period,
      'page': page,
      'pageSize': pageSize,
    };
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is WalletEntryParams &&
            other.currency == currency &&
            other.walletOwner == walletOwner &&
            other.fiscalYear == fiscalYear &&
            other.period == period &&
            other.page == page &&
            other.pageSize == pageSize;
  }

  @override
  int get hashCode {
    return Object.hash(
      currency,
      walletOwner,
      fiscalYear,
      period,
      page,
      pageSize,
    );
  }
}
