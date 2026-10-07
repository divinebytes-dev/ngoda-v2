import 'package:ngoda/data_models/common/report_pagination.dart';
import 'package:ngoda/services/number_conversion_service.dart';

class IncompleteTransactionRow {
  const IncompleteTransactionRow({
    required this.id,
    required this.sourceType,
    required this.recordId,
    required this.recordStatus,
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
    required this.errorMessage,
    required this.explorerUrl,
    required this.createdBy,
    required this.createdAt,
    required this.liquidationJobId,
    required this.userId,
    required this.blockchainQueueId,
    required this.blockchainStatus,
    required this.retryCount,
    required this.totalPrincipal,
    required this.totalInterest,
    required this.totalDebt,
    required this.penaltyAmount,
    required this.repaymentRequired,
    required this.collateralRequired,
    required this.goldPrice,
    required this.email,
    required this.phone,
    required this.firstName,
    required this.surname,
  });

  final String id;

  /// Backend source classification.
  final String sourceType;

  final String recordId;
  final String? recordStatus;

  final int period;
  final int fiscalYear;

  final String? countryCode;

  final String? transactionHash;
  final String? documentNumber;
  final String? reference;

  final String? transactionType;

  final String? sender;
  final String? receiver;

  final double quantity;
  final double grossAmount;
  final double netAmount;
  final double feeAmount;

  final String? currencyCode;

  final String? chain;
  final String? chainStatus;

  final String? description;
  final String? errorMessage;

  final String? explorerUrl;
  final String? createdBy;

  final DateTime? createdAt;

  final String? liquidationJobId;
  final String? userId;

  final String? blockchainQueueId;
  final String? blockchainStatus;

  final int retryCount;

  final double totalPrincipal;
  final double totalInterest;
  final double totalDebt;

  final double penaltyAmount;
  final double repaymentRequired;

  final double collateralRequired;
  final double goldPrice;

  final String? email;
  final String? phone;
  final String? firstName;
  final String? surname;

  factory IncompleteTransactionRow.fromJson(Map<String, dynamic> json) {
    final id = _string(json['id']);

    return IncompleteTransactionRow(
      id: id,
      sourceType: _string(json['source_type']).toLowerCase(),
      recordId: _nullableString(json['record_id']) ?? id,
      recordStatus: _nullableString(json['record_status'])?.toLowerCase(),
      period: NumberConversionService.toInt(json['period']),
      fiscalYear: NumberConversionService.toInt(json['fiscal_year']),
      countryCode: _nullableString(json['country_code'])?.toLowerCase(),
      transactionHash: _nullableString(json['tx_hash']),
      documentNumber: _nullableString(json['document_number']),
      reference: _nullableString(json['reference']),
      transactionType: _nullableString(json['transaction_type'])?.toLowerCase(),
      sender: _nullableString(json['sender']),
      receiver: _nullableString(json['receiver']),
      quantity: NumberConversionService.toDouble(json['quantity']),
      grossAmount: NumberConversionService.toDouble(json['gross_amount']),
      netAmount: NumberConversionService.toDouble(json['net_amount']),
      feeAmount: NumberConversionService.toDouble(json['fee_amount']),
      currencyCode: _nullableString(json['currency_code'])?.toLowerCase(),
      chain: _nullableString(json['chain'])?.toLowerCase(),
      chainStatus: _nullableString(json['chain_status'])?.toLowerCase(),
      description: _nullableString(json['description']),
      errorMessage: _nullableString(json['error_message']),
      explorerUrl: _nullableString(json['explorer_url']),
      createdBy: _nullableString(json['created_by']),
      createdAt: _dateTime(json['created_at']),
      liquidationJobId: _nullableString(json['liquidation_job_id']),
      userId: _nullableString(json['user_id']),
      blockchainQueueId: _nullableString(json['blockchain_queue_id']),
      blockchainStatus: _nullableString(
        json['blockchain_status'],
      )?.toLowerCase(),
      retryCount: NumberConversionService.toInt(json['retry_count']),
      totalPrincipal: NumberConversionService.toDouble(json['total_principal']),
      totalInterest: NumberConversionService.toDouble(json['total_interest']),
      totalDebt: NumberConversionService.toDouble(json['total_debt']),
      penaltyAmount: NumberConversionService.toDouble(json['penalty_amount']),
      repaymentRequired: NumberConversionService.toDouble(
        json['repayment_required'],
      ),
      collateralRequired: NumberConversionService.toDouble(
        json['collateral_required'],
      ),
      goldPrice: NumberConversionService.toDouble(json['gold_price']),
      email: _nullableString(json['email']),
      phone: _nullableString(json['phone']),
      firstName: _nullableString(json['first_name']),
      surname: _nullableString(json['surname']),
    );
  }

  bool get hasError => errorMessage != null;

  bool get hasRetried => retryCount > 0;

  bool get hasTransactionHash => transactionHash != null;

  bool get hasBlockchainQueue => blockchainQueueId != null;

  String? get effectiveStatus {
    return recordStatus ?? blockchainStatus ?? chainStatus;
  }

  String get effectiveReference {
    return documentNumber ?? reference ?? recordId;
  }

  String get borrowerName {
    final names = <String>[
      if (firstName != null) firstName!,
      if (surname != null) surname!,
    ];

    if (names.isNotEmpty) {
      return names.join(' ');
    }

    return email ?? phone ?? userId ?? sender ?? recordId;
  }
}

class IncompleteBlockchainTransactions {
  IncompleteBlockchainTransactions({
    required List<IncompleteTransactionRow> transactions,
    required this.pagination,
  }) : transactions = List.unmodifiable(transactions);

  final List<IncompleteTransactionRow> transactions;

  final ReportPagination pagination;

  factory IncompleteBlockchainTransactions.fromJson(Map<String, dynamic> json) {
    final paginationJson = json['pagination'];

    return IncompleteBlockchainTransactions(
      transactions: _mapList(
        json['rows'],
      ).map(IncompleteTransactionRow.fromJson).toList(),
      pagination: paginationJson is Map
          ? ReportPagination.fromJson(Map<String, dynamic>.from(paginationJson))
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

  int get pageRecordCount => transactions.length;

  int get totalRecordCount => pagination.totalEntries;

  int get errorCount => transactions.where((record) => record.hasError).length;

  int get retriedCount =>
      transactions.where((record) => record.hasRetried).length;

  List<IncompleteTransactionRow> recordsForSourceType(String sourceType) {
    final normalized = sourceType.trim().toLowerCase();

    return List.unmodifiable(
      transactions.where((record) => record.sourceType == normalized),
    );
  }

  List<IncompleteTransactionRow> get recordsWithErrors {
    return List.unmodifiable(transactions.where((record) => record.hasError));
  }

  Map<String, double> get grossAmountByCurrency {
    final totals = <String, double>{};

    for (final record in transactions) {
      final currency = record.currencyCode;

      if (currency == null || currency.isEmpty) {
        continue;
      }

      totals[currency] = (totals[currency] ?? 0) + record.grossAmount;
    }

    return Map.unmodifiable(totals);
  }
}

String _string(dynamic value) {
  return value?.toString().trim() ?? '';
}

String? _nullableString(dynamic value) {
  final result = value?.toString().trim();

  if (result == null || result.isEmpty) {
    return null;
  }

  return result;
}

DateTime? _dateTime(dynamic value) {
  final result = _nullableString(value);

  if (result == null) {
    return null;
  }

  return DateTime.tryParse(result);
}

List<Map<String, dynamic>> _mapList(dynamic value) {
  if (value is! List) {
    return const [];
  }

  return value
      .whereType<Map>()
      .map((entry) => Map<String, dynamic>.from(entry))
      .toList();
}
