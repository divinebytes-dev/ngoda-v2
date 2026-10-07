import 'package:ngoda/data_models/gl/gl_currency_balance.dart';
import 'package:ngoda/data_models/gl/gl_totals.dart';
import 'package:ngoda/services/number_conversion_service.dart';

class GLBalanceSummary {
  GLBalanceSummary({
    required this.fiscalYear,
    required this.period,
    required Map<String, GLTotals> totals,
    required Map<String, GLCurrencyBalance> data,
  }) : totals = Map.unmodifiable(totals),
       data = Map.unmodifiable(data);

  final int fiscalYear;
  final int period;

  final Map<String, GLTotals> totals;

  final Map<String, GLCurrencyBalance> data;

  factory GLBalanceSummary.fromJson(Map<String, dynamic> json) {
    return GLBalanceSummary(
      fiscalYear: NumberConversionService.toInt(json['fiscalYear']),
      period: NumberConversionService.toInt(json['period']),
      totals: _parseTotals(json['totals']),
      data: _parseBalances(json['data']),
    );
  }

  GLCurrencyBalance? byCurrency(String currency) {
    return data[currency.trim().toLowerCase()];
  }

  GLTotals? totalsByCurrency(String currency) {
    return totals[currency.trim().toLowerCase()];
  }

  bool containsCurrency(String currency) {
    return data.containsKey(currency.trim().toLowerCase());
  }

  List<String> get currencies {
    return List.unmodifiable(data.keys);
  }

  List<String> get sortedCurrencies {
    final result = [...data.keys]..sort();

    return List.unmodifiable(result);
  }

  static Map<String, GLTotals> _parseTotals(dynamic value) {
    if (value is! Map) {
      return const {};
    }

    final result = <String, GLTotals>{};

    for (final entry in value.entries) {
      if (entry.value is! Map) {
        continue;
      }

      final currency = entry.key.toString().trim().toLowerCase();

      if (currency.isEmpty) {
        continue;
      }

      result[currency] = GLTotals.fromJson(
        Map<String, dynamic>.from(entry.value as Map),
      );
    }

    return result;
  }

  static Map<String, GLCurrencyBalance> _parseBalances(dynamic value) {
    if (value is! Map) {
      return const {};
    }

    final result = <String, GLCurrencyBalance>{};

    for (final entry in value.entries) {
      if (entry.value is! Map) {
        continue;
      }

      final currency = entry.key.toString().trim().toLowerCase();

      if (currency.isEmpty) {
        continue;
      }

      result[currency] = GLCurrencyBalance.fromJson(
        Map<String, dynamic>.from(entry.value as Map),
      );
    }

    return result;
  }
}
