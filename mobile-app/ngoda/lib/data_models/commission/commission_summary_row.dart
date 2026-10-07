import 'package:ngoda/services/number_conversion_service.dart';

class CommissionSummaryRow {
  const CommissionSummaryRow({
    required this.transactionType,
    required this.currencyCode,
    required this.agents,
    required this.totalAmount,
    required this.totalFeeAmount,
    required this.totalCommissionAmount,
  });

  final String transactionType;
  final String currencyCode;

  final int agents;

  final double totalAmount;
  final double totalFeeAmount;
  final double totalCommissionAmount;

  factory CommissionSummaryRow.fromJson(Map<String, dynamic> json) {
    return CommissionSummaryRow(
      transactionType:
          json['transaction_type']?.toString().trim().toLowerCase() ?? '',
      currencyCode:
          json['currency_code']?.toString().trim().toLowerCase() ?? '',
      agents: NumberConversionService.toInt(json['agents']),
      totalAmount: NumberConversionService.toDouble(json['total_amount']),
      totalFeeAmount: NumberConversionService.toDouble(
        json['total_fee_amount'],
      ),
      totalCommissionAmount: NumberConversionService.toDouble(
        json['total_commission_amount'],
      ),
    );
  }
}
