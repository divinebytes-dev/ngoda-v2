import 'package:ngoda/services/number_conversion_service.dart';

class CurrencyBalance {
  const CurrencyBalance({required this.balance, required this.usdValue});

  final double balance;
  final double usdValue;

  factory CurrencyBalance.fromJson(Map<String, dynamic> json) {
    return CurrencyBalance(
      balance: NumberConversionService.toDouble(json['balance']),
      usdValue: NumberConversionService.toDouble(json['usd_value']),
    );
  }
}
