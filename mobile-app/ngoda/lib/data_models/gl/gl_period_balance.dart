import 'package:ngoda/services/number_conversion_service.dart';

class GLPeriodBalance {
  const GLPeriodBalance({
    required this.period,
    required this.opening,
    required this.debit,
    required this.credit,
    required this.closing,
  });

  final int period;

  final double opening;
  final double debit;
  final double credit;
  final double closing;

  factory GLPeriodBalance.fromJson(Map<String, dynamic> json) {
    return GLPeriodBalance(
      period: NumberConversionService.toInt(json['period']),
      opening: NumberConversionService.toDouble(json['opening_balance']),
      debit: NumberConversionService.toDouble(json['debit']),
      credit: NumberConversionService.toDouble(json['credit']),
      closing: NumberConversionService.toDouble(json['closing_balance']),
    );
  }

  bool get hasActivity => debit != 0 || credit != 0;
}
