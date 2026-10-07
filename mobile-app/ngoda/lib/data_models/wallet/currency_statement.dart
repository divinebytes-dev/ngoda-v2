import 'package:ngoda/data_models/wallet/wallet_transaction.dart';
import 'package:ngoda/services/number_conversion_service.dart';
import 'package:ngoda/data_models/common/report_pagination.dart';

class CurrencyStatement {
  CurrencyStatement({
    required List<WalletTransaction> transactions,
    required this.totalDebit,
    required this.totalCredit,
    required this.balance,
    required this.pageOpeningBalance,
    required this.pageClosingBalance,
    required this.pagination,
  }) : transactions = List.unmodifiable(transactions);

  final List<WalletTransaction> transactions;

  final double totalDebit;
  final double totalCredit;

  /// Backend-provided current balance.
  final double balance;

  /// Opening balance before the first
  /// transaction on this page.
  final double pageOpeningBalance;

  /// Closing balance after the last
  /// transaction on this page.
  final double pageClosingBalance;

  final ReportPagination pagination;

  factory CurrencyStatement.fromJson(Map<String, dynamic> json) {
    return CurrencyStatement(
      transactions: _parseTransactions(json['transactions']),
      totalDebit: NumberConversionService.toDouble(json['total_debit']),
      totalCredit: NumberConversionService.toDouble(json['total_credit']),
      balance: NumberConversionService.toDouble(json['balance']),
      pageOpeningBalance: NumberConversionService.toDouble(
        json['page_opening_balance'],
      ),
      pageClosingBalance: NumberConversionService.toDouble(
        json['page_closing_balance'],
      ),
      pagination: ReportPagination.fromJson(_asMap(json['pagination'])),
    );
  }

  bool get isEmpty => transactions.isEmpty;

  bool get isNotEmpty => transactions.isNotEmpty;

  int get transactionCount => transactions.length;

  double get movement => totalCredit - totalDebit;

  static List<WalletTransaction> _parseTransactions(dynamic value) {
    if (value is! List) {
      return const [];
    }

    return value
        .whereType<Map>()
        .map(
          (transaction) => WalletTransaction.fromJson(
            Map<String, dynamic>.from(transaction),
          ),
        )
        .toList();
  }

  static Map<String, dynamic> _asMap(dynamic value) {
    if (value is Map) {
      return Map<String, dynamic>.from(value);
    }

    return const {};
  }
}
