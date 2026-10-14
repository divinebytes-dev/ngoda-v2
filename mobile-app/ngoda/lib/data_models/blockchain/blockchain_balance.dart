import 'package:ngoda/services/number_conversion_service.dart';

class BlockchainBalance {
  const BlockchainBalance({
    required this.blockchainCode,
    required this.chainId,
    required this.tokenSupply,
    required this.balance,
    required this.gasBalance,
    required this.nativeCurrencyCode,
  });

  final String blockchainCode;
  final int chainId;

  /// Total token supply on this blockchain.
  final double tokenSupply;

  /// Token balance belonging to the requested wallet.
  final double balance;

  /// Native gas currency balance belonging to the requested wallet.
  final double gasBalance;

  final String nativeCurrencyCode;

  factory BlockchainBalance.fromJson(Map<String, dynamic> json) {
    return BlockchainBalance(
      blockchainCode:
          json['blockchain_code']?.toString().trim().toLowerCase() ?? '',
      chainId: int.tryParse(json['chain_id']?.toString() ?? '') ?? 0,
      tokenSupply: NumberConversionService.toDouble(json['token_supply']),
      balance: NumberConversionService.toDouble(json['balance']),
      gasBalance: NumberConversionService.toDouble(json['gas_balance']),
      nativeCurrencyCode:
          json['native_currency_code']?.toString().trim().toUpperCase() ?? '',
    );
  }
}
