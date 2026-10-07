class TransferCalculationResult {
  const TransferCalculationResult({
    required this.amount,
    required this.fee,
    required this.tax,
    required this.totalDebit,
  });

  final double amount;

  final double fee;

  final double tax;

  final double totalDebit;
}
