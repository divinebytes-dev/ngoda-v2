import 'package:ngoda/data_models/reserve-bank/reserve_bank_periodic_tax.dart';

class TaxPeriodDrilldown {
  TaxPeriodDrilldown.fromJson(Map<String, dynamic> json)
    : summary = ReserveBankTaxPeriodBalance.fromJson(
        Map<String, dynamic>.from(json['summary'] as Map),
      ),
      page = json['page'] as int,
      pageSize = json['page_size'] as int,
      totalEntries = json['total_entries'] as int,
      entries = List.unmodifiable(
        (json['entries'] as List).map(
          (row) =>
              TaxPeriodEntry.fromJson(Map<String, dynamic>.from(row as Map)),
        ),
      );

  final ReserveBankTaxPeriodBalance summary;
  final int page;
  final int pageSize;
  final int totalEntries;
  final List<TaxPeriodEntry> entries;

  int get totalPages => (totalEntries + pageSize - 1) ~/ pageSize;
  bool get hasPrevious => page > 1;
  bool get hasNext => page < totalPages;
}

class TaxPeriodEntry {
  TaxPeriodEntry.fromJson(Map<String, dynamic> json)
    : documentNumber = json['document_number'] as String,
      transactionType = json['transaction_type'] as String,
      grossAmount = (json['gross_amount'] as Object).toString(),
      taxAmount = (json['tax_amount'] as Object).toString(),
      taxRate = json['tax_rate']?.toString(),
      isSettled = json['is_settled'] as bool;

  final String documentNumber;
  final String transactionType;
  final String grossAmount;
  final String taxAmount;
  final String? taxRate;
  final bool isSettled;
}
