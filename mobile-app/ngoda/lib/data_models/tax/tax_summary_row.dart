import 'package:ngoda/services/number_conversion_service.dart';

class TaxSummaryRow {
  const TaxSummaryRow({
    required this.transactionType,
    required this.currencyCode,
    required this.totalTaxAmount,
    required this.totalGrossAmount,
  });

  final String transactionType;
  final String currencyCode;

  final double totalTaxAmount;
  final double totalGrossAmount;

  factory TaxSummaryRow.fromJson(Map<String, dynamic> json) {
    return TaxSummaryRow(
      transactionType:
          json['transaction_type']?.toString().trim().toLowerCase() ?? '',
      currencyCode:
          json['currency_code']?.toString().trim().toLowerCase() ?? '',
      totalTaxAmount: NumberConversionService.toDouble(
        json['total_tax_amount'],
      ),
      totalGrossAmount: NumberConversionService.toDouble(
        json['total_gross_amount'],
      ),
    );
  }

  double get effectiveTaxRate {
    if (totalGrossAmount == 0) {
      return 0;
    }

    return (totalTaxAmount / totalGrossAmount) * 100;
  }
}
