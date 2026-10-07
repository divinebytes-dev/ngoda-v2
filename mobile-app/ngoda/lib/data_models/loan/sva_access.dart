import 'package:ngoda/services/number_conversion_service.dart';

class SvaAccess {
  const SvaAccess({
    required this.activeLoans,
    required this.maxActiveLoans,
    required this.utilisationPercent,
    required this.canAccess,
  });

  final int activeLoans;
  final int maxActiveLoans;

  final double utilisationPercent;

  /// Backend-authoritative access decision.
  final bool canAccess;

  factory SvaAccess.fromJson(Map<String, dynamic> json) {
    return SvaAccess(
      activeLoans: NumberConversionService.toInt(json['active_loans']),
      maxActiveLoans: NumberConversionService.toInt(json['max_active_loans']),
      utilisationPercent: NumberConversionService.toDouble(
        json['utilisation_percent'],
      ),
      canAccess: json['can_access'] == true,
    );
  }

  int get remainingLoanSlots {
    final remaining = maxActiveLoans - activeLoans;

    return remaining > 0 ? remaining : 0;
  }

  bool get hasRemainingLoanSlots => remainingLoanSlots > 0;
}
