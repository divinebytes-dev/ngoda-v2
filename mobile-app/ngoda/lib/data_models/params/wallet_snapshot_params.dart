class WalletSnapshotParams {
  WalletSnapshotParams({required String currency, required String walletOwner})
    : currency = currency.trim().toLowerCase(),
      walletOwner = walletOwner.trim().toLowerCase();

  final String currency;
  final String walletOwner;

  WalletSnapshotParams copyWith({String? currency, String? walletOwner}) {
    return WalletSnapshotParams(
      currency: currency ?? this.currency,
      walletOwner: walletOwner ?? this.walletOwner,
    );
  }

  Map<String, dynamic> toQueryParameters() {
    return {'currency': currency, 'walletOwner': walletOwner};
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is WalletSnapshotParams &&
            other.currency == currency &&
            other.walletOwner == walletOwner;
  }

  @override
  int get hashCode {
    return Object.hash(currency, walletOwner);
  }
}
