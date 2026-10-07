import 'package:ngoda/data_models/currency/currency.dart';
import 'package:ngoda/data_models/currency/currency_registry.dart';
import 'package:ngoda/data_models/treasury/treasury_wallet.dart';
import 'package:ngoda/services/currency_service.dart';
import 'package:ngoda/services/number_conversion_service.dart';

class TreasuryDashboard {
  TreasuryDashboard({
    required this.goldReserve,
    required this.tokenSupply,
    required this.gasBalance,
    required this.reserveRatio,
    required this.treasuryWallet,
    required List<Currency> currencies,
    required this.currencyRegistry,
  }) : currencies = List.unmodifiable(currencies);

  final double goldReserve;
  final double tokenSupply;

  final double gasBalance;

  /// Backend-calculated reserve ratio.
  final double reserveRatio;

  final List<Currency> currencies;

  final CurrencyRegistry currencyRegistry;

  final TreasuryWallet treasuryWallet;

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

    final currencies = _parseCurrencies(json['currencies']);

    CurrencyService.initialize(currencies);

    return TreasuryDashboard(
      goldReserve: NumberConversionService.toDouble(json['gold_reserve']),
      tokenSupply: NumberConversionService.toDouble(json['token_supply']),
      gasBalance: NumberConversionService.toDouble(json['gas_balance']),
      reserveRatio: NumberConversionService.toDouble(json['reserve_ratio']),
      treasuryWallet: TreasuryWallet.fromJson(walletMap),
      currencies: currencies,
      currencyRegistry: CurrencyRegistry.fromCurrencies(currencies),
    );
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
  /// 🔥 reserve coverage %
  double get reserveCoveragePercent => reserveRatio * 100;

  /// 🔥 healthy reserve
  bool get isHealthyReserve => reserveRatio >= 1;

  /// 🔥 wallet USD value
  double get treasuryUsdValue => treasuryWallet.totalUsdValue;
  double get excessReserve => goldReserve - tokenSupply;

  bool get isFullyBacked => reserveRatio >= 1;

  double get reservePercentage => reserveRatio * 100;

  /// 🔥 formatted reserve status
  String get reserveStatus {
    if (reserveRatio >= 1) {
      return "Healthy";
    }

    if (reserveRatio >= 0.75) {
      return "Warning";
    }

    return "Critical";
  }
}
