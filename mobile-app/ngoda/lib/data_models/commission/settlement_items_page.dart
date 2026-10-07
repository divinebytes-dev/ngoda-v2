import 'package:ngoda/data_models/commission/settlement_item.dart';
import 'package:ngoda/data_models/common/report_pagination.dart';
import 'package:ngoda/services/number_conversion_service.dart';

class SettlementItemsPage {
  SettlementItemsPage({
    required List<SettlementItem> items,
    required this.totalAgents,
    required this.currency,
    required this.totalAmount,
    required this.pagination,
  }) : items = List.unmodifiable(items);

  final int totalAgents;

  final String currency;

  final double totalAmount;

  final List<SettlementItem> items;

  final ReportPagination pagination;

  factory SettlementItemsPage.fromJson(Map<String, dynamic> json) {
    final rawData = json['data'];

    final payload = rawData is Map ? Map<String, dynamic>.from(rawData) : json;

    final rawItems = payload['items'];

    final rawPagination = payload['pagination'];

    return SettlementItemsPage(
      totalAgents: NumberConversionService.toInt(payload['totalAgents']),
      currency: payload['currency']?.toString().trim().toLowerCase() ?? '',
      totalAmount: NumberConversionService.toDouble(payload['totalAmount']),
      items: rawItems is List
          ? rawItems
                .whereType<Map>()
                .map(
                  (item) =>
                      SettlementItem.fromJson(Map<String, dynamic>.from(item)),
                )
                .toList()
          : const [],
      pagination: rawPagination is Map
          ? ReportPagination.fromJson(Map<String, dynamic>.from(rawPagination))
          : ReportPagination.empty(),
    );
  }

  bool get hasItems => items.isNotEmpty;

  int get itemCount => items.length;

  SettlementItem? get firstItem {
    return items.isEmpty ? null : items.first;
  }

  SettlementItem? get lastItem {
    return items.isEmpty ? null : items.last;
  }
}
