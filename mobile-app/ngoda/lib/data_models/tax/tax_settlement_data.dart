import 'dart:collection';

import 'package:ngoda/data_models/tax/tax_settlement_batch.dart';
import 'package:ngoda/data_models/tax/tax_settlement_item.dart';

class TaxSettlementData {
  TaxSettlementData({
    required List<TaxSettlementBatch> batches,
    required List<TaxSettlementItem> items,
  }) : batches = List.unmodifiable(batches),
       items = List.unmodifiable(items);

  final List<TaxSettlementBatch> batches;
  final List<TaxSettlementItem> items;

  factory TaxSettlementData.fromJson(Map<String, dynamic> json) {
    final rawData = json['data'];

    final data = rawData is Map ? Map<String, dynamic>.from(rawData) : json;

    return TaxSettlementData(
      batches: _parseBatches(data['settlementBatch']),
      items: _parseItems(data['settlementItems']),
    );
  }

  List<TaxSettlementItem> itemsForBatch(String batchId) {
    final normalized = batchId.trim();

    return List.unmodifiable(items.where((item) => item.batchId == normalized));
  }

  Map<String, List<TaxSettlementItem>> get itemsGrouped {
    final grouped = <String, List<TaxSettlementItem>>{};

    for (final item in items) {
      grouped.putIfAbsent(item.batchId, () => []).add(item);
    }

    return UnmodifiableMapView({
      for (final entry in grouped.entries)
        entry.key: List.unmodifiable(entry.value),
    });
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

  List<String> get currencyList {
    return List.unmodifiable(
      batches.map((batch) => batch.currencyCode).toSet(),
    );
  }

  List<String> get sortedCurrencyList {
    final currencies = currencyList.toList()..sort();

    return List.unmodifiable(currencies);
  }

  List<TaxSettlementItem> itemsForCurrencyAndStatus(
    String currency,
    String status,
  ) {
    final batch = batchByCurrencyAndStatus(currency, status);

    if (batch == null) {
      return const [];
    }

    return itemsForBatch(batch.id);
  }

  TaxSettlementData byCurrency(String currency) {
    final normalized = _normalize(currency);

    final filteredBatches = batches
        .where((batch) => batch.currencyCode == normalized)
        .toList();

    final batchIds = filteredBatches.map((batch) => batch.id).toSet();

    final filteredItems = items
        .where((item) => batchIds.contains(item.batchId))
        .toList();

    return TaxSettlementData(batches: filteredBatches, items: filteredItems);
  }

  static List<TaxSettlementBatch> _parseBatches(dynamic value) {
    if (value is! List) {
      return const [];
    }

    return value
        .whereType<Map>()
        .map(
          (row) => TaxSettlementBatch.fromJson(Map<String, dynamic>.from(row)),
        )
        .toList();
  }

  static List<TaxSettlementItem> _parseItems(dynamic value) {
    if (value is! List) {
      return const [];
    }

    return value
        .whereType<Map>()
        .map(
          (row) => TaxSettlementItem.fromJson(Map<String, dynamic>.from(row)),
        )
        .toList();
  }

  static String _normalize(String value) {
    return value.trim().toLowerCase();
  }
}
