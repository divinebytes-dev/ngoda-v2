class FinanceSummaryResult {
  const FinanceSummaryResult({
    required this.financeCash,
    required this.agentNet,
    required this.creditAgentNet,
    required this.customerDeposit,
    required this.netPosition,
  });

  final double financeCash;
  final double agentNet;
  final double creditAgentNet;
  final double customerDeposit;
  final double netPosition;
}
