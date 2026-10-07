import 'package:ngoda/data_models/commission/settlement_batch.dart';

class SettlementBatchData {
  SettlementBatchData({required List<SettlementBatch> batches})
    : batches = List.unmodifiable(batches);

  final List<SettlementBatch> batches;

  factory SettlementBatchData.fromJson(Map<String, dynamic> json) {
    final rawData = json['data'];

    final data = rawData is Map ? Map<String, dynamic>.from(rawData) : json;

    final rawBatches = data['settlementBatch'];

    return SettlementBatchData(
      batches: rawBatches is List
          ? rawBatches
                .whereType<Map>()
                .map(
                  (row) =>
                      SettlementBatch.fromJson(Map<String, dynamic>.from(row)),
                )
                .toList()
          : const [],
    );
  }

  bool get isEmpty => batches.isEmpty;

  bool get isNotEmpty => batches.isNotEmpty;

  SettlementBatch? getById(String batchId) {
    final normalized = batchId.trim();

    for (final batch in batches) {
      if (batch.id == normalized) {
        return batch;
      }
    }

    return null;
  }

  List<SettlementBatch> byCurrency(String currency) {
    final normalized = currency.trim().toLowerCase();

    return List.unmodifiable(
      batches.where((batch) => batch.currencyCode == normalized),
    );
  }

  SettlementBatch? batchByCurrencyAndStatus(String currency, String status) {
    final normalizedCurrency = currency.trim().toLowerCase();

    final normalizedStatus = status.trim().toLowerCase();

    for (final batch in batches) {
      if (batch.currencyCode == normalizedCurrency &&
          batch.status == normalizedStatus) {
        return batch;
      }
    }

    return null;
  }

  SettlementBatch? batchByCurrency(String currency) {
    final normalized = currency.trim().toLowerCase();

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
}
