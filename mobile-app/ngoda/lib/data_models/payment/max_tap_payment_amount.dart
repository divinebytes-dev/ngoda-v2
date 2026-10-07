import 'package:ngoda/services/number_conversion_service.dart';

class MaxTapPaymentAmount {
  const MaxTapPaymentAmount({
    required this.currencyCode,
    required this.maxAmount,
    required this.isActive,
  });

  final String currencyCode;
  final double maxAmount;
  final bool isActive;

  factory MaxTapPaymentAmount.fromJson(Map<String, dynamic> json) {
    return MaxTapPaymentAmount(
      currencyCode:
          json['currency_code']?.toString().trim().toLowerCase() ?? '',
      maxAmount: NumberConversionService.toDouble(json['express_tap_limit']),
      isActive: json['is_active'] == true,
    );
  }
}
