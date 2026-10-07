import 'package:ngoda/data_models/common/report_pagination.dart';
import 'package:ngoda/data_models/tax/tax_settlement_item.dart';
import 'package:ngoda/services/number_conversion_service.dart';

class TaxSettlementItemsPage {
  TaxSettlementItemsPage({
    required List<TaxSettlementItem> items,
    required this.totalTransactions,
    required this.currency,
    required this.totalAmount,
    required this.pagination,
  }) : items = List.unmodifiable(items);

  final int totalTransactions;
  final String currency;
  final double totalAmount;
  final List<TaxSettlementItem> items;
  final ReportPagination pagination;

  factory TaxSettlementItemsPage.fromJson(Map<String, dynamic> json) {
    final rawData = json['data'];

    final payload = rawData is Map ? Map<String, dynamic>.from(rawData) : json;

    final rawItems = payload['items'];

    final rawPagination = payload['pagination'];

    return TaxSettlementItemsPage(
      totalTransactions: NumberConversionService.toInt(payload['totalItems']),
      currency: payload['currency']?.toString().trim().toLowerCase() ?? '',
      totalAmount: NumberConversionService.toDouble(payload['totalAmount']),
      items: rawItems is List
          ? rawItems
                .whereType<Map>()
                .map(
                  (item) => TaxSettlementItem.fromJson(
                    Map<String, dynamic>.from(item),
                  ),
                )
                .toList()
          : const [],
      pagination: rawPagination is Map
          ? ReportPagination.fromJson(Map<String, dynamic>.from(rawPagination))
          : const ReportPagination(
              page: 1,
              pageSize: 50,
              totalEntries: 0,
              totalPages: 1,
              hasPrevious: false,
              hasNext: false,
            ),
    );
  }

  bool get hasItems => items.isNotEmpty;

  int get itemCount => items.length;

  TaxSettlementItem? get firstItem => items.isEmpty ? null : items.first;

  TaxSettlementItem? get lastItem => items.isEmpty ? null : items.last;
}
