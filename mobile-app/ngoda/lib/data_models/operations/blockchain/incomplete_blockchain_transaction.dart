import 'package:ngoda/data_models/common/report_pagination.dart';
import 'package:ngoda/services/number_conversion_service.dart';

class IncompleteBlockchainTransactions {
  IncompleteBlockchainTransactions({
    required List<BlockchainTransaction> transactions,
    required this.pagination,
  }) : transactions = List.unmodifiable(transactions);

  final List<BlockchainTransaction> transactions;
  final ReportPagination pagination;

  factory IncompleteBlockchainTransactions.fromJson(Map<String, dynamic> json) {
    return IncompleteBlockchainTransactions(
      transactions: _parseTransactions(json['transactions']),
      pagination: json['pagination'] is Map
          ? ReportPagination.fromJson(
              Map<String, dynamic>.from(json['pagination'] as Map),
            )
          : ReportPagination.empty(),
    );
  }

  factory IncompleteBlockchainTransactions.empty() {
    return IncompleteBlockchainTransactions(
      transactions: const [],
      pagination: ReportPagination.empty(),
    );
  }

  bool get isEmpty => transactions.isEmpty;

  bool get isNotEmpty => transactions.isNotEmpty;

  int get pageCount => transactions.length;

  int get totalCount => pagination.totalEntries;

  List<BlockchainTransaction> get withErrors {
    return List.unmodifiable(
      transactions.where((transaction) => transaction.chainStatus != null),
    );
  }

  static List<BlockchainTransaction> _parseTransactions(dynamic value) {
    if (value is! List) {
      return const [];
    }

    return value
        .whereType<Map>()
        .map(
          (item) =>
              BlockchainTransaction.fromJson(Map<String, dynamic>.from(item)),
        )
        .toList();
  }
}

class BlockchainTransaction {
  const BlockchainTransaction({
    required this.id,
    required this.period,
    required this.fiscalYear,
    required this.countryCode,
    required this.transactionHash,
    required this.documentNumber,
    required this.reference,
    required this.transactionType,
    required this.sender,
    required this.receiver,
    required this.quantity,
    required this.grossAmount,
    required this.netAmount,
    required this.feeAmount,
    required this.currencyCode,
    required this.chain,
    required this.chainStatus,
    required this.description,
    required this.explorerUrl,
    required this.status,
    required this.createdBy,
    required this.createdAt,
  });

  final String id;

  final int period;
  final int fiscalYear;

  final String countryCode;

  final String transactionHash;

  final String? documentNumber;
  final String? reference;

  /// Dynamic backend transaction type.
  final String transactionType;

  final String sender;
  final String receiver;

  final double quantity;
  final double grossAmount;
  final double netAmount;
  final double feeAmount;

  final String currencyCode;

  final String chain;
  final String? chainStatus;

  final String? description;
  final String? explorerUrl;

  /// Dynamic backend transaction status.
  final String status;

  final String createdBy;
  final DateTime createdAt;

  factory BlockchainTransaction.fromJson(Map<String, dynamic> json) {
    return BlockchainTransaction(
      id: _requiredString(json['id'], 'id'),
      period: NumberConversionService.toInt(json['period']),
      fiscalYear: NumberConversionService.toInt(json['fiscal_year']),
      countryCode: _requiredString(
        json['country_code'],
        'country_code',
      ).toLowerCase(),
      transactionHash: _requiredString(json['tx_hash'], 'tx_hash'),
      documentNumber: _nullableString(json['document_number']),
      reference: _nullableString(json['reference']),
      transactionType: _requiredString(
        json['transaction_type'],
        'transaction_type',
      ).toLowerCase(),
      sender: _requiredString(json['sender'], 'sender'),
      receiver: _requiredString(json['receiver'], 'receiver'),
      quantity: NumberConversionService.toDouble(json['quantity']),
      grossAmount: NumberConversionService.toDouble(json['gross_amount']),
      netAmount: NumberConversionService.toDouble(json['net_amount']),
      feeAmount: NumberConversionService.toDouble(json['fee_amount']),
      currencyCode: _requiredString(
        json['currency_code'],
        'currency_code',
      ).toLowerCase(),
      chain: _requiredString(json['chain'], 'chain').toLowerCase(),
      chainStatus: _nullableString(json['chain_status'])?.toLowerCase(),
      description: _nullableString(json['description']),
      explorerUrl: _nullableString(json['explorer_url']),
      status: _requiredString(json['status'], 'status').toLowerCase(),
      createdBy: _requiredString(json['created_by'], 'created_by'),
      createdAt: _requiredDateTime(json['created_at'], 'created_at'),
    );
  }

  bool get hasDocument => documentNumber != null;

  bool get hasReference => reference != null;

  bool get hasExplorerUrl => explorerUrl != null;
}

String _requiredString(dynamic value, String field) {
  final result = value?.toString().trim();

  if (result == null || result.isEmpty) {
    throw FormatException('BlockchainTransaction.$field is required.');
  }

  return result;
}

String? _nullableString(dynamic value) {
  final result = value?.toString().trim();

  if (result == null || result.isEmpty) {
    return null;
  }

  return result;
}

DateTime _requiredDateTime(dynamic value, String field) {
  final raw = _nullableString(value);

  if (raw == null) {
    throw FormatException('BlockchainTransaction.$field is required.');
  }

  final parsed = DateTime.tryParse(raw);

  if (parsed == null) {
    throw FormatException('BlockchainTransaction.$field is invalid.');
  }

  return parsed;
}
