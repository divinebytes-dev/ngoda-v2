import 'package:ngoda/data_models/loan/loan_risk.dart';
import 'package:ngoda/services/number_conversion_service.dart';

class LoanPreview {
  const LoanPreview({
    required this.onchainBalance,
    required this.lockedCollateral,
    required this.availableTokens,
    required this.collateralValue,
    required this.requestedAmount,
    required this.marketPricePerGram,
    required this.maxBorrowable,
    required this.requiredCollateralGrams,
    required this.initiationFee,
    required this.netDisbursed,
    required this.ltvPercent,
    required this.liquidationLtvPercent,
    required this.risk,
  });

  final double onchainBalance;
  final double lockedCollateral;
  final double availableTokens;

  final double collateralValue;
  final double requestedAmount;

  final double marketPricePerGram;

  final double maxBorrowable;
  final double requiredCollateralGrams;

  final double initiationFee;
  final double netDisbursed;

  final double ltvPercent;
  final double liquidationLtvPercent;

  final LoanRisk risk;

  factory LoanPreview.fromJson(Map<String, dynamic> json) {
    return LoanPreview(
      onchainBalance: NumberConversionService.toDouble(json['onchain_balance']),
      lockedCollateral: NumberConversionService.toDouble(
        json['locked_collateral'],
      ),
      availableTokens: NumberConversionService.toDouble(
        json['available_tokens'],
      ),
      collateralValue: NumberConversionService.toDouble(
        json['collateral_value'],
      ),
      requestedAmount: NumberConversionService.toDouble(
        json['requested_amount'],
      ),
      marketPricePerGram: NumberConversionService.toDouble(
        json['market_price_per_gram'],
      ),
      maxBorrowable: NumberConversionService.toDouble(json['max_borrowable']),
      requiredCollateralGrams: NumberConversionService.toDouble(
        json['required_collateral_grams'],
      ),
      initiationFee: NumberConversionService.toDouble(json['initiation_fee']),
      netDisbursed: NumberConversionService.toDouble(json['net_disbursed']),
      ltvPercent: NumberConversionService.toDouble(json['ltv_percent']),
      liquidationLtvPercent: NumberConversionService.toDouble(
        json['liquidation_ltv_percent'],
      ),
      risk: LoanRisk.fromJson(_asMap(json['risk'])),
    );
  }

  bool get hasAvailableTokens => availableTokens > 0;

  bool get canBorrowRequestedAmount =>
      requestedAmount > 0 && requestedAmount <= maxBorrowable;

  static Map<String, dynamic> _asMap(dynamic value) {
    if (value is Map) {
      return Map<String, dynamic>.from(value);
    }

    return const {};
  }
}
