import 'dart:collection';

import 'package:ngoda/data_models/accounts/accounts_kpi_by_currency.dart';
import 'package:ngoda/data_models/commission/last_commission_settlement_dates.dart';
import 'package:ngoda/data_models/currency/currency.dart';
import 'package:ngoda/data_models/currency/currency_registry.dart';
import 'package:ngoda/data_models/financial-statements/balance-sheet/balance_sheet_by_currency.dart';
import 'package:ngoda/services/currency_service.dart';
import 'package:ngoda/services/number_conversion_service.dart';

class AccountsDashboard {
  AccountsDashboard({
    required this.kpi,
    required this.balanceSheet,
    required List<Currency> currencies,
    required this.currencyRegistry,
    required Map<String, double> bankNet,
    required this.lastCommissionSettlementDates,
    required this.lastGovernmentTaxSettlementDates,
  }) : currencies = List.unmodifiable(currencies),
       bankNet = UnmodifiableMapView(_normalizeBankNet(bankNet));

  final AccountsKPIByCurrency kpi;

  final BalanceSheetByCurrency balanceSheet;

  final List<Currency> currencies;

  final CurrencyRegistry currencyRegistry;

  final Map<String, double> bankNet;

  final LastCommissionSettlementDates lastCommissionSettlementDates;

  final LastCommissionSettlementDates lastGovernmentTaxSettlementDates;

  factory AccountsDashboard.fromJson(Map<String, dynamic> json) {
    final currencies = _parseCurrencies(json['currencies']);

    CurrencyService.initialize(currencies);

    return AccountsDashboard(
      kpi: AccountsKPIByCurrency.fromJson(_asJsonMap(json['kpi'])),
      balanceSheet: BalanceSheetByCurrency.fromJson(
        _asJsonMap(json['balance_sheet_snapshot']),
      ),
      currencies: currencies,
      currencyRegistry: CurrencyRegistry.fromCurrencies(currencies),
      bankNet: _parseBankNet(json['bank_net']),
      lastCommissionSettlementDates: LastCommissionSettlementDates.fromJson(
        _asJsonMap(json['agent_commission_settlements']),
      ),
      lastGovernmentTaxSettlementDates: LastCommissionSettlementDates.fromJson(
        _asJsonMap(json['government_tax_settlements']),
      ),
    );
  }

  double bankNetBalance(String currency) {
    return bankNet[_normalizeCurrency(currency)] ?? 0.0;
  }

  bool hasBankNetForCurrency(String currency) {
    return bankNet.containsKey(_normalizeCurrency(currency));
  }

  List<String> get bankNetCurrencyList => List.unmodifiable(bankNet.keys);

  List<String> get sortedBankNetCurrencyList {
    final currencies = bankNet.keys.toList()..sort();

    return List.unmodifiable(currencies);
  }

  List<MapEntry<String, double>> get bankNetCurrencyEntries =>
      List.unmodifiable(bankNet.entries);

  static List<Currency> _parseCurrencies(dynamic value) {
    if (value is! List) {
      return const [];
    }

    final currencies = <Currency>[];

    for (final item in value) {
      if (item is Map<String, dynamic>) {
        currencies.add(Currency.fromJson(item));

        continue;
      }

      if (item is Map) {
        currencies.add(Currency.fromJson(Map<String, dynamic>.from(item)));
      }
    }

    return currencies;
  }

  static Map<String, double> _parseBankNet(dynamic value) {
    if (value is! Map) {
      return const {};
    }

    final bankNet = <String, double>{};

    for (final entry in value.entries) {
      final currency = _normalizeCurrency(entry.key.toString());

      if (currency.isEmpty) {
        continue;
      }

      bankNet[currency] = NumberConversionService.toDouble(entry.value);
    }

    return bankNet;
  }

  static Map<String, double> _normalizeBankNet(Map<String, double> value) {
    final normalized = <String, double>{};

    for (final entry in value.entries) {
      final currency = _normalizeCurrency(entry.key);

      if (currency.isEmpty) {
        continue;
      }

      normalized[currency] = entry.value;
    }

    return normalized;
  }

  static Map<String, dynamic> _asJsonMap(dynamic value) {
    if (value is Map<String, dynamic>) {
      return value;
    }

    if (value is Map) {
      return Map<String, dynamic>.from(value);
    }

    return const {};
  }

  static String _normalizeCurrency(String value) {
    return value.trim().toLowerCase();
  }
}

extension AccountsDashboardBankNetX on AccountsDashboard {
  double bankNetBalance(String currency) {
    return bankNet[currency.toLowerCase()] ?? 0;
  }

  List<String> get bankNetCurrencyList => bankNet.keys.toList();

  List<String> get sortedBankNetCurrencyList => [...bankNet.keys]..sort();

  List<MapEntry<String, double>> get bankNetCurrencyEntries =>
      bankNet.entries.toList();

  double get totalBankNet =>
      bankNet.values.fold(0.0, (sum, value) => sum + value);
}
