import 'package:ngoda/data_models/currency/currency.dart';
import 'package:ngoda/data_models/finance/finance_bucket.dart';

class FinanceSummary {
  FinanceSummary({
    required this.bank,
    required this.treasury,
    required this.agentAsset,
    required this.agentFloat,
    required this.customer,
    required this.creditAgentFloat,
    required this.creditAgentCash,
    required List<Currency> currencies,
  }) : currencies = List.unmodifiable(currencies);

  final FinanceBucket bank;
  final FinanceBucket treasury;

  final FinanceBucket agentAsset;
  final FinanceBucket agentFloat;

  final FinanceBucket customer;

  final FinanceBucket creditAgentFloat;
  final FinanceBucket creditAgentCash;

  final List<Currency> currencies;

  factory FinanceSummary.fromJson(Map<String, dynamic> json) {
    return FinanceSummary(
      bank: FinanceBucket.fromJson(_asMap(json['bank'])),
      treasury: FinanceBucket.fromJson(_asMap(json['treasury'])),
      agentAsset: FinanceBucket.fromJson(_asMap(json['agentAsset'])),
      agentFloat: FinanceBucket.fromJson(_asMap(json['agentFloat'])),
      customer: FinanceBucket.fromJson(_asMap(json['customer'])),
      creditAgentFloat: FinanceBucket.fromJson(
        _asMap(json['creditAgentFloat']),
      ),
      creditAgentCash: FinanceBucket.fromJson(_asMap(json['creditAgentCash'])),
      currencies: _parseCurrencies(json['currencies']),
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

  static Map<String, dynamic> _asMap(dynamic value) {
    if (value is Map) {
      return Map<String, dynamic>.from(value);
    }

    return const {};
  }
}
