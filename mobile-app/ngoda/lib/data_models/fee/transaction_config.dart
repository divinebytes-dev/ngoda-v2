import 'package:ngoda/data_models/fee/fee_by_currency.dart';
import 'package:ngoda/data_models/fee/fee_config.dart';

class TransactionConfig {
  TransactionConfig({required Map<String, FeeByCurrency> fees})
    : fees = Map.unmodifiable(fees);

  final Map<String, FeeByCurrency> fees;

  factory TransactionConfig.fromJson(Map<String, dynamic> json) {
    final result = <String, FeeByCurrency>{};

    for (final entry in json.entries) {
      if (entry.value is! Map) {
        continue;
      }

      final transactionType = entry.key.trim().toLowerCase();

      if (transactionType.isEmpty) {
        continue;
      }

      result[transactionType] = FeeByCurrency.fromJson(
        Map<String, dynamic>.from(entry.value as Map),
      );
    }

    return TransactionConfig(fees: result);
  }

  FeeConfig? get(String transactionType, String currency) {
    return fees[transactionType.trim().toLowerCase()]?.forCurrency(currency);
  }

  FeeByCurrency? forTransactionType(String transactionType) {
    return fees[transactionType.trim().toLowerCase()];
  }

  bool containsTransactionType(String transactionType) {
    return fees.containsKey(transactionType.trim().toLowerCase());
  }

  List<String> get transactionTypes {
    return List.unmodifiable(fees.keys);
  }

  bool get isEmpty => fees.isEmpty;
  bool get isNotEmpty => fees.isNotEmpty;
}
