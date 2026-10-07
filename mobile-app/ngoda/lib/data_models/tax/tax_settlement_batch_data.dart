import 'package:ngoda/data_models/tax/tax_settlement_batch.dart';

class TaxSettlementBatchData {
  TaxSettlementBatchData({required List<TaxSettlementBatch> batches})
    : batches = List.unmodifiable(batches);

  final List<TaxSettlementBatch> batches;

  factory TaxSettlementBatchData.fromJson(Map<String, dynamic> json) {
    final rawData = json['data'];

    final data = rawData is Map ? Map<String, dynamic>.from(rawData) : json;

    final rawBatches = data['settlementBatch'];

    final batches = <TaxSettlementBatch>[];

    if (rawBatches is List) {
      for (final row in rawBatches) {
        if (row is Map) {
          batches.add(
            TaxSettlementBatch.fromJson(Map<String, dynamic>.from(row)),
          );
        }
      }
    }

    return TaxSettlementBatchData(batches: batches);
  }

  bool get isEmpty => batches.isEmpty;

  bool get isNotEmpty => batches.isNotEmpty;

  TaxSettlementBatch? getById(String batchId) {
    final normalized = batchId.trim();

    for (final batch in batches) {
      if (batch.id == normalized) {
        return batch;
      }
    }

    return null;
  }

  List<TaxSettlementBatch> byCurrency(String currency) {
    final normalized = _normalize(currency);

    return List.unmodifiable(
      batches.where((batch) => batch.currencyCode == normalized),
    );
  }

  TaxSettlementBatch? batchByCurrencyAndStatus(String currency, String status) {
    final normalizedCurrency = _normalize(currency);

    final normalizedStatus = _normalize(status);

    for (final batch in batches) {
      if (batch.currencyCode == normalizedCurrency &&
          batch.status == normalizedStatus) {
        return batch;
      }
    }

    return null;
  }

  TaxSettlementBatch? batchByCurrency(String currency) {
    final normalized = _normalize(currency);

    for (final batch in batches) {
      if (batch.currencyCode == normalized) {
        return batch;
      }
    }

    return null;
  }

  List<String> get currencyList {
    return List.unmodifiable(
      batches.map((batch) => batch.currencyCode).toSet(),
    );
  }

  List<String> get sortedCurrencyList {
    final currencies = currencyList.toList()..sort();

    return List.unmodifiable(currencies);
  }

  static String _normalize(String value) {
    return value.trim().toLowerCase();
  }
}
