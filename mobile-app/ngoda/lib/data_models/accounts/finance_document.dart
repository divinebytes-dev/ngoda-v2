import 'package:ngoda/data_models/accounts/journal_line.dart';
import 'package:ngoda/data_models/accounts/wallet_line.dart';
import 'package:ngoda/services/number_conversion_service.dart';

class FinanceDocument {
  FinanceDocument({
    required this.documentNumber,
    this.reversalDocumentNumber,
    required this.transactionType,
    required this.currency,
    required this.totalDebit,
    required this.totalCredit,
    required this.balanced,
    required List<JournalLine> journal,
    required List<WalletLine> wallet,
  }) : journal = List.unmodifiable(journal),
       wallet = List.unmodifiable(wallet);

  final String documentNumber;
  final String? reversalDocumentNumber;

  final String transactionType;
  final String currency;

  final double totalDebit;
  final double totalCredit;

  final bool balanced;

  final List<JournalLine> journal;
  final List<WalletLine> wallet;

  factory FinanceDocument.fromJson(Map<String, dynamic> json) {
    return FinanceDocument(
      documentNumber: json['document_number']?.toString().trim() ?? '',
      reversalDocumentNumber: _nullableString(json['reversal_document_number']),
      transactionType:
          json['transaction_type']?.toString().trim().toLowerCase() ?? '',
      currency: json['currency']?.toString().trim().toLowerCase() ?? '',
      totalDebit: NumberConversionService.toDouble(json['total_debit']),
      totalCredit: NumberConversionService.toDouble(json['total_credit']),
      balanced: json['balanced'] == true,
      journal: _parseList(json['journal'], JournalLine.fromJson),
      wallet: _parseList(json['wallet'], WalletLine.fromJson),
    );
  }

  bool get isReversal => reversalDocumentNumber != null;

  bool get hasJournalEntries => journal.isNotEmpty;

  bool get hasWalletEntries => wallet.isNotEmpty;

  static List<T> _parseList<T>(
    dynamic value,
    T Function(Map<String, dynamic>) parser,
  ) {
    if (value is! List) {
      return const [];
    }

    return value
        .whereType<Map>()
        .map((item) => parser(Map<String, dynamic>.from(item)))
        .toList();
  }

  static String? _nullableString(dynamic value) {
    if (value == null) {
      return null;
    }

    final result = value.toString().trim();

    return result.isEmpty ? null : result;
  }
}
