import 'package:ngoda/services/number_conversion_service.dart';

class BlockchainWalletBalance {
  const BlockchainWalletBalance({
    required this.blockchainCode,
    required this.currencyCode,
    required this.balance,
    required this.usdValue,
  });

  final String blockchainCode;
  final String currencyCode;
  final double balance;
  final double usdValue;

  factory BlockchainWalletBalance.fromJson(Map<String, dynamic> json) {
    return BlockchainWalletBalance(
      blockchainCode:
          json['blockchain_code']?.toString().trim().toLowerCase() ?? '',
      currencyCode:
          json['currency_code']?.toString().trim().toLowerCase() ?? '',
      balance: NumberConversionService.toDouble(json['balance']),
      usdValue: NumberConversionService.toDouble(json['usd_value']),
    );
  }
}
