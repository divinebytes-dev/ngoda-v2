import 'package:ngoda/services/number_conversion_service.dart';

class GLTotals {
  const GLTotals({
    required this.opening,
    required this.debit,
    required this.credit,
    required this.closing,
  });

  final double opening;
  final double debit;
  final double credit;
  final double closing;

  factory GLTotals.fromJson(Map<String, dynamic> json) {
    return GLTotals(
      opening: NumberConversionService.toDouble(json['opening']),
      debit: NumberConversionService.toDouble(json['debit']),
      credit: NumberConversionService.toDouble(json['credit']),
      closing: NumberConversionService.toDouble(json['closing']),
    );
  }

  bool get hasActivity => debit != 0 || credit != 0;
}
