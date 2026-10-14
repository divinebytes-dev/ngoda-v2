class WalletSnapshotParams {
  WalletSnapshotParams({
    required String currency,
    required String walletOwner,
    String? blockchainCode,
  }) : currency = currency.trim().toLowerCase(),
       walletOwner = walletOwner.trim().toLowerCase(),
       blockchainCode = _normalizeBlockchainCode(blockchainCode) {
    _validate();
  }

  final String currency;
  final String walletOwner;
  final String? blockchainCode;

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

  WalletSnapshotParams copyWith({
    String? currency,
    String? walletOwner,
    String? blockchainCode,
    bool clearBlockchainCode = false,
  }) {
    return WalletSnapshotParams(
      currency: currency ?? this.currency,
      walletOwner: walletOwner ?? this.walletOwner,
      blockchainCode: clearBlockchainCode
          ? null
          : blockchainCode ?? this.blockchainCode,
    );
  }

  Map<String, dynamic> toQueryParameters() {
    _validate();

    return {
      'currency': currency,
      'walletOwner': walletOwner,
      if (blockchainCode != null) 'blockchainCode': blockchainCode,
    };
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is WalletSnapshotParams &&
            other.currency == currency &&
            other.walletOwner == walletOwner &&
            other.blockchainCode == blockchainCode;
  }

  @override
  int get hashCode {
    return Object.hash(currency, walletOwner, blockchainCode);
  }
}
