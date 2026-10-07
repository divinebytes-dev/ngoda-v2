class GoldCalculationResult {
  const GoldCalculationResult({
    required this.principal,
    required this.quantity,
    required this.fiatPaid,
    required this.fiatFee,
    required this.feeGold,
    required this.spreadProfit,
  });

  final double principal;
  final double quantity;

  final double fiatPaid;
  final double fiatFee;

  final double feeGold;

  final double spreadProfit;
}
