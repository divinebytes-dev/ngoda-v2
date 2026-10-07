import 'package:ngoda/data_models/loan/sva_access.dart';
import 'package:ngoda/data_models/customer/loan_gold_summary.dart';
import 'package:ngoda/services/number_conversion_service.dart';

class LoanSummary {
  const LoanSummary({
    required this.principalOutstanding,
    required this.interestOutstanding,
    required this.collateralLocked,
    required this.requiredCollateral,
    required this.ltvPercent,
    required this.health,
    required this.svaAccess,
    required this.gold,
  });

  final double principalOutstanding;
  final double interestOutstanding;

  final double collateralLocked;
  final double requiredCollateral;

  final double ltvPercent;

  /// Loan health value returned by the backend.
  final String health;

  final SvaAccess svaAccess;
  final LoanGoldSummary gold;

  factory LoanSummary.fromJson(Map<String, dynamic> json) {
    final data = _asMap(json['summary'] ?? json);

    return LoanSummary(
      principalOutstanding: NumberConversionService.toDouble(
        data['principal_outstanding'],
      ),
      interestOutstanding: NumberConversionService.toDouble(
        data['interest_outstanding'],
      ),
      collateralLocked: NumberConversionService.toDouble(
        data['collateral_locked'],
      ),
      requiredCollateral: NumberConversionService.toDouble(
        data['required_collateral'],
      ),
      ltvPercent: NumberConversionService.toDouble(data['ltv_percent']),
      health: (data['health'] ?? '').toString().trim().toLowerCase(),
      svaAccess: SvaAccess.fromJson(_asMap(data['sva_access'])),
      gold: LoanGoldSummary.fromJson(_asMap(data['gold'])),
    );
  }

  double get totalOutstanding => principalOutstanding + interestOutstanding;

  bool get hasOutstandingLoan => totalOutstanding > 0;

  bool get hasPrincipalOutstanding => principalOutstanding > 0;

  bool get hasInterestOutstanding => interestOutstanding > 0;

  bool get hasCollateral => collateralLocked > 0;

  bool get isSafe => health == 'safe';

  bool get isWarning => health == 'warning';

  bool get isDanger => health == 'liquidation_risk' || health == 'danger';

  bool get canAccessSva => svaAccess.canAccess;

  double get availableCollateralPercent => gold.availablePercent;

  double get lockedCollateralPercent => gold.lockedPercent;

  static Map<String, dynamic> _asMap(dynamic value) {
    if (value is Map) {
      return Map<String, dynamic>.from(value);
    }

    return const {};
  }
}
