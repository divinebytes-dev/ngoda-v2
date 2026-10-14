class WalletEntryParams {
  WalletEntryParams({
    required String currency,
    required String walletOwner,
    required this.fiscalYear,
    required this.period,
    String? blockchainCode,
    this.page = 1,
    this.pageSize = 50,
  }) : currency = currency.trim().toLowerCase(),
       walletOwner = walletOwner.trim().toLowerCase(),
       blockchainCode = _normalizeBlockchainCode(blockchainCode) {
    _validate();
  }

  final String currency;
  final String walletOwner;
  final String? blockchainCode;

  final int fiscalYear;
  final int period;

  final int page;
  final int pageSize;

  static String? _normalizeBlockchainCode(String? value) {
    final normalized = value?.trim().toLowerCase();

    if (normalized == null || normalized.isEmpty) {
      return null;
    }

    return normalized;
  }

  void _validate() {
    if (currency == 'gold' && blockchainCode == null) {
      throw ArgumentError('blockchainCode is required when currency is gold.');
    }
  }

  WalletEntryParams copyWith({
    String? currency,
    String? walletOwner,
    String? blockchainCode,
    bool clearBlockchainCode = false,
    int? fiscalYear,
    int? period,
    int? page,
    int? pageSize,
  }) {
    return WalletEntryParams(
      currency: currency ?? this.currency,
      walletOwner: walletOwner ?? this.walletOwner,
      blockchainCode: clearBlockchainCode
          ? null
          : blockchainCode ?? this.blockchainCode,
      fiscalYear: fiscalYear ?? this.fiscalYear,
      period: period ?? this.period,
      page: page ?? this.page,
      pageSize: pageSize ?? this.pageSize,
    );
  }

  Map<String, dynamic> toQueryParameters() {
    _validate();

    return {
      'currency': currency,
      'walletOwner': walletOwner,
      if (blockchainCode != null) 'blockchainCode': blockchainCode,
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
            other.blockchainCode == blockchainCode &&
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
      blockchainCode,
      fiscalYear,
      period,
      page,
      pageSize,
    );
  }
}
