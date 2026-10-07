enum LoyaltyLedgerType {
  earn,
  redeem,
  reverse,
  expire,
  adjustment,
  unknown;

  static LoyaltyLedgerType fromApiValue(dynamic value) {
    final normalized = value?.toString().trim().toLowerCase();

    return LoyaltyLedgerType.values.firstWhere(
      (type) => type != LoyaltyLedgerType.unknown && type.name == normalized,
      orElse: () => LoyaltyLedgerType.unknown,
    );
  }
}
