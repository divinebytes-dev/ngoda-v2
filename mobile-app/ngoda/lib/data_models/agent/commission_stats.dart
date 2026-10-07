import 'package:ngoda/services/number_conversion_service.dart';

class CommissionStats {
  const CommissionStats({
    required this.totalAmount,
    required this.totalFee,
    required this.totalCommission,
    required this.paid,
    required this.notPaid,
  });

  final double totalAmount;
  final double totalFee;
  final double totalCommission;
  final double paid;
  final double notPaid;

  factory CommissionStats.fromJson(Map<String, dynamic> json) {
    return CommissionStats(
      totalAmount: NumberConversionService.toDouble(json['total_amount']),
      totalFee: NumberConversionService.toDouble(json['total_fee']),
      totalCommission: NumberConversionService.toDouble(
        json['total_commission'],
      ),
      paid: NumberConversionService.toDouble(json['paid']),
      notPaid: NumberConversionService.toDouble(json['not_paid']),
    );
  }

  bool get hasCommission => totalCommission != 0;

  bool get hasPaidCommission => paid != 0;

  bool get hasUnpaidCommission => notPaid != 0;
}
