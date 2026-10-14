import 'package:ngoda/data_models/blockchain/blockchain_balance.dart';
import 'package:ngoda/data_models/currency/currency.dart';
import 'package:ngoda/data_models/currency/currency_registry.dart';
import 'package:ngoda/data_models/treasury/treasury_wallet.dart';
import 'package:ngoda/services/currency_service.dart';
import 'package:ngoda/services/number_conversion_service.dart';

class TreasuryDashboard {
  TreasuryDashboard({
    required this.goldReserve,
    required this.tokenSupply,
    required this.treasuryGoldBalance,
    required this.reserveRatio,
    required this.treasuryWallet,
    required List<BlockchainBalance> blockchainBalances,
    required List<Currency> currencies,
    required this.currencyRegistry,
  }) : blockchainBalances = List.unmodifiable(blockchainBalances),
       currencies = List.unmodifiable(currencies);

  final double goldReserve;

  /// Consolidated token supply across supported blockchains.
  final double tokenSupply;

  /// Consolidated Treasury gold holdings across supported blockchains.
  final double treasuryGoldBalance;

  /// Backend-calculated reserve ratio.
  final double reserveRatio;

  /// Consolidated Treasury balances, grouped by currency.
  final TreasuryWallet treasuryWallet;

  /// Individual blockchain balances.
  final List<BlockchainBalance> blockchainBalances;

  final List<Currency> currencies;

  final CurrencyRegistry currencyRegistry;

  factory TreasuryDashboard.fromJson(Map<String, dynamic> json) {
    final walletMap = <String, dynamic>{};

    final walletList = json['treasury_wallet_balances'];

    if (walletList is List) {
      for (final item in walletList) {
        if (item is! Map) {
          continue;
        }

        final map = Map<String, dynamic>.from(item);

        final currencyCode = map['currency_code']
            ?.toString()
            .trim()
            .toLowerCase();

        if (currencyCode == null || currencyCode.isEmpty) {
          continue;
        }

        walletMap[currencyCode] = map;
      }
    }

    final blockchainBalances = _parseBlockchainBalances(
      json['blockchain_balances'],
    );

    final currencies = _parseCurrencies(json['currencies']);

    CurrencyService.initialize(currencies);

    return TreasuryDashboard(
      goldReserve: NumberConversionService.toDouble(json['gold_reserve']),
      tokenSupply: NumberConversionService.toDouble(json['token_supply']),
      treasuryGoldBalance: NumberConversionService.toDouble(
        json['treasury_gold_balance'],
      ),
      reserveRatio: NumberConversionService.toDouble(json['reserve_ratio']),
      treasuryWallet: TreasuryWallet.fromJson(walletMap),
      blockchainBalances: blockchainBalances,
      currencies: currencies,
      currencyRegistry: CurrencyRegistry.fromCurrencies(currencies),
    );
  }

  static List<BlockchainBalance> _parseBlockchainBalances(dynamic value) {
    if (value is! List) {
      return const [];
    }

    return value
        .whereType<Map>()
        .map(
          (blockchain) =>
              BlockchainBalance.fromJson(Map<String, dynamic>.from(blockchain)),
        )
        .toList();
  }

  static List<Currency> _parseCurrencies(dynamic value) {
    if (value is! List) {
      return const [];
    }

    return value
        .whereType<Map>()
        .map(
          (currency) => Currency.fromJson(Map<String, dynamic>.from(currency)),
        )
        .toList();
  }
}

extension TreasuryDashboardX on TreasuryDashboard {
  /// Reserve coverage percentage.
  double get reserveCoveragePercent => reserveRatio * 100;

  /// Healthy reserve.
  bool get isHealthyReserve => reserveRatio >= 1;

  /// Consolidated Treasury wallet USD value.
  double get treasuryUsdValue => treasuryWallet.totalUsdValue;

  /// Physical reserve less issued gold tokens.
  double get excessReserve => goldReserve - tokenSupply;

  bool get isFullyBacked => reserveRatio >= 1;

  double get reservePercentage => reserveRatio * 100;

  /// Find an individual blockchain balance.
  BlockchainBalance? getBlockchainBalance(String blockchainCode) {
    final code = blockchainCode.trim().toLowerCase();

    for (final blockchain in blockchainBalances) {
      if (blockchain.blockchainCode == code) {
        return blockchain;
      }
    }

    return null;
  }

  bool hasBlockchain(String blockchainCode) {
    return getBlockchainBalance(blockchainCode) != null;
  }

  /// Total number of active blockchains returned by the backend.
  int get blockchainCount => blockchainBalances.length;

  /// Formatted reserve status.
  String get reserveStatus {
    if (reserveRatio >= 1) {
      return 'Healthy';
    }

    if (reserveRatio >= 0.75) {
      return 'Warning';
    }

    return 'Critical';
  }
}
