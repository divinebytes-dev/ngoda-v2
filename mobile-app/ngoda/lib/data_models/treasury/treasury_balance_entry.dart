import 'package:ngoda/services/number_conversion_service.dart';

class TreasuryBalanceEntry {
  const TreasuryBalanceEntry({
    required this.currencyCode,
    required this.debit,
    required this.credit,
    required this.opening,
    required this.closing,
  });

  final String currencyCode;

  final double debit;
  final double credit;

  final double opening;
  final double closing;

  factory TreasuryBalanceEntry.fromJson(Map<String, dynamic> json) {
    return TreasuryBalanceEntry(
      currencyCode:
          json['currency_code']?.toString().trim().toLowerCase() ?? '',
      debit: NumberConversionService.toDouble(json['debit']),
      credit: NumberConversionService.toDouble(json['credit']),
      opening: NumberConversionService.toDouble(json['opening_balance']),
      closing: NumberConversionService.toDouble(json['closing_balance']),
    );
  }

  double get movement => credit - debit;

  bool get hasActivity => debit != 0 || credit != 0;

  bool get isPositive => closing >= 0;

  bool get isNegative => closing < 0;
}
