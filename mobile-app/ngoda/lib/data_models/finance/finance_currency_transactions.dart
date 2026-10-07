import 'package:ngoda/data_models/finance/finance_transaction.dart';
import 'package:ngoda/data_models/common/report_pagination.dart';

class FinanceCurrencyTransactions {
  FinanceCurrencyTransactions({
    required this.pagination,
    required List<FinanceTransaction> transactions,
  }) : transactions = List.unmodifiable(transactions);

  final ReportPagination pagination;

  final List<FinanceTransaction> transactions;

  factory FinanceCurrencyTransactions.fromJson(Map<String, dynamic> json) {
    final rawTransactions = json['transactions'];

    return FinanceCurrencyTransactions(
      pagination: ReportPagination.fromJson(_asMap(json['pagination'])),
      transactions: rawTransactions is List
          ? rawTransactions
                .whereType<Map>()
                .map(
                  (transaction) => FinanceTransaction.fromJson(
                    Map<String, dynamic>.from(transaction),
                  ),
                )
                .toList()
          : const [],
    );
  }

  bool get isEmpty => transactions.isEmpty;

  bool get isNotEmpty => transactions.isNotEmpty;

  int get currentPage => pagination.page;

  int get totalPages => pagination.totalPages;

  int get totalEntries => pagination.totalEntries;

  bool get hasPrevious => pagination.hasPrevious;

  bool get hasNext => pagination.hasNext;

  static Map<String, dynamic> _asMap(dynamic value) {
    if (value is Map) {
      return Map<String, dynamic>.from(value);
    }

    return const {};
  }
}
