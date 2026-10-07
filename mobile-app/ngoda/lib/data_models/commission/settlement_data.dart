import 'dart:collection';

import 'package:ngoda/data_models/commission/settlement_batch.dart';
import 'package:ngoda/data_models/commission/settlement_item.dart';

class SettlementData {
  SettlementData({
    required List<SettlementBatch> batches,
    required List<SettlementItem> items,
  }) : batches = List.unmodifiable(batches),
       items = List.unmodifiable(items);

  final List<SettlementBatch> batches;
  final List<SettlementItem> items;

  factory SettlementData.fromJson(Map<String, dynamic> json) {
    final rawData = json['data'];

    final data = rawData is Map ? Map<String, dynamic>.from(rawData) : json;

    return SettlementData(
      batches: _parseBatches(data['settlementBatch']),
      items: _parseItems(data['settlementItems']),
    );
  }

  List<SettlementItem> itemsForBatch(String batchId) {
    return List.unmodifiable(items.where((item) => item.batchId == batchId));
  }

  Map<String, List<SettlementItem>> get itemsGrouped {
    final grouped = <String, List<SettlementItem>>{};

    for (final item in items) {
      grouped.putIfAbsent(item.batchId, () => []).add(item);
    }

    return UnmodifiableMapView({
      for (final entry in grouped.entries)
        entry.key: List.unmodifiable(entry.value),
    });
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

  List<String> get currencyList {
    return List.unmodifiable(
      batches.map((batch) => batch.currencyCode).toSet(),
    );
  }

  List<String> get sortedCurrencyList {
    final currencies = currencyList.toList()..sort();

    return List.unmodifiable(currencies);
  }

  double totalCommissionForBatch(String batchId) {
    return itemsForBatch(
      batchId,
    ).fold(0.0, (total, item) => total + item.totalCommission);
  }

  List<SettlementItem> itemsForCurrencyAndStatus(
    String currency,
    String status,
  ) {
    final batch = batchByCurrencyAndStatus(currency, status);

    if (batch == null) {
      return const [];
    }

    return itemsForBatch(batch.id);
  }

  SettlementData byCurrency(String currency) {
    final normalized = currency.trim().toLowerCase();

    final filteredBatches = batches
        .where((batch) => batch.currencyCode == normalized)
        .toList();

    final batchIds = filteredBatches.map((batch) => batch.id).toSet();

    final filteredItems = items
        .where((item) => batchIds.contains(item.batchId))
        .toList();

    return SettlementData(batches: filteredBatches, items: filteredItems);
  }

  static List<SettlementBatch> _parseBatches(dynamic value) {
    if (value is! List) {
      return const [];
    }

    return value
        .whereType<Map>()
        .map((row) => SettlementBatch.fromJson(Map<String, dynamic>.from(row)))
        .toList();
  }

  static List<SettlementItem> _parseItems(dynamic value) {
    if (value is! List) {
      return const [];
    }

    return value
        .whereType<Map>()
        .map((row) => SettlementItem.fromJson(Map<String, dynamic>.from(row)))
        .toList();
  }
}
