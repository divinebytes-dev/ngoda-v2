import 'package:ngoda/data_models/currency/currency_balance.dart';

class CreditAgentCurrencyBalance {
  const CreditAgentCurrencyBalance({
    required this.cashOwed,
    required this.receivableBalance,
    required this.isActive,
  });

  final CurrencyBalance cashOwed;
  final CurrencyBalance receivableBalance;

  final bool isActive;

  factory CreditAgentCurrencyBalance.fromJson(Map<String, dynamic> json) {
    return CreditAgentCurrencyBalance(
      cashOwed: CurrencyBalance.fromJson(_asMap(json['cashOwed'])),
      receivableBalance: CurrencyBalance.fromJson(
        _asMap(json['receivableBalance']),
      ),
      isActive: json['isActive'] == true,
    );
  }

  bool get hasCashOwed => cashOwed.balance > 0;

  bool get hasReceivableBalance => receivableBalance.balance > 0;

  bool get hasOutstandingBalance => hasCashOwed || hasReceivableBalance;
}

class CreditAgentWallet {
  CreditAgentWallet({
    required Map<String, CreditAgentCurrencyBalance> currencies,
  }) : currencies = Map.unmodifiable(
         currencies.map(
           (currency, balance) =>
               MapEntry(currency.trim().toLowerCase(), balance),
         ),
       );

  final Map<String, CreditAgentCurrencyBalance> currencies;

  factory CreditAgentWallet.fromJson(Map<String, dynamic> json) {
    final rawBalances = _asMap(json['balances']);

    final balances = <String, CreditAgentCurrencyBalance>{};

    for (final entry in rawBalances.entries) {
      final currency = entry.key.trim().toLowerCase();

      if (currency.isEmpty) {
        continue;
      }

      final value = entry.value;

      if (value is! Map) {
        continue;
      }

      balances[currency] = CreditAgentCurrencyBalance.fromJson(
        Map<String, dynamic>.from(value),
      );
    }

    return CreditAgentWallet(currencies: balances);
  }

  factory CreditAgentWallet.empty() {
    return CreditAgentWallet(currencies: const {});
  }

  CreditAgentCurrencyBalance? operator [](String currency) {
    return getByCurrency(currency);
  }

  CreditAgentCurrencyBalance? getByCurrency(String currency) {
    return currencies[currency.trim().toLowerCase()];
  }

  bool hasCurrency(String currency) {
    return currencies.containsKey(currency.trim().toLowerCase());
  }

  bool isCurrencyActive(String currency) {
    return getByCurrency(currency)?.isActive ?? false;
  }

  CurrencyBalance? cashOwed(String currency) {
    return getByCurrency(currency)?.cashOwed;
  }

  CurrencyBalance? receivableBalance(String currency) {
    return getByCurrency(currency)?.receivableBalance;
  }

  bool get isEmpty => currencies.isEmpty;

  bool get isNotEmpty => currencies.isNotEmpty;
}

extension CreditAgentWalletX on CreditAgentWallet {
  List<String> get currencyList {
    return List.unmodifiable(currencies.keys);
  }

  List<String> get sortedCurrencyList {
    final result = [...currencies.keys]..sort();

    return List.unmodifiable(result);
  }

  List<String> get activeCurrencyList {
    final result =
        currencies.entries
            .where((entry) => entry.value.isActive)
            .map((entry) => entry.key)
            .toList()
          ..sort();

    return List.unmodifiable(result);
  }

  List<MapEntry<String, CreditAgentCurrencyBalance>> get currencyEntries {
    final result = currencies.entries.toList()
      ..sort((first, second) => first.key.compareTo(second.key));

    return List.unmodifiable(result);
  }

  double get totalCashOwedUsd {
    return currencies.values.fold(
      0.0,
      (total, balance) => total + balance.cashOwed.usdValue,
    );
  }

  double get totalReceivableUsd {
    return currencies.values.fold(
      0.0,
      (total, balance) => total + balance.receivableBalance.usdValue,
    );
  }

  double get totalOutstandingUsd {
    return totalCashOwedUsd + totalReceivableUsd;
  }
}

Map<String, dynamic> _asMap(dynamic value) {
  if (value is Map) {
    return Map<String, dynamic>.from(value);
  }

  return const {};
}
