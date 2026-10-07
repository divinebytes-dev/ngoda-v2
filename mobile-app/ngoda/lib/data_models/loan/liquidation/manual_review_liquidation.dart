import 'package:ngoda/services/number_conversion_service.dart';
import 'package:ngoda/data_models/common/report_pagination.dart';

enum ManualReviewAction {
  verifyOnChain,
  verifyStoredTransaction,
  resumeAccounting,
  unknown;

  factory ManualReviewAction.fromCode(dynamic value) {
    final code = value?.toString().trim().toUpperCase();

    return switch (code) {
      'VERIFY_ON_CHAIN' => ManualReviewAction.verifyOnChain,
      'VERIFY_STORED_TRANSACTION' => ManualReviewAction.verifyStoredTransaction,
      'RESUME_ACCOUNTING' => ManualReviewAction.resumeAccounting,
      _ => ManualReviewAction.unknown,
    };
  }

  String get code {
    return switch (this) {
      ManualReviewAction.verifyOnChain => 'VERIFY_ON_CHAIN',
      ManualReviewAction.verifyStoredTransaction => 'VERIFY_STORED_TRANSACTION',
      ManualReviewAction.resumeAccounting => 'RESUME_ACCOUNTING',
      ManualReviewAction.unknown => 'UNKNOWN',
    };
  }
}

class ManualReviewLiquidationRow {
  const ManualReviewLiquidationRow({
    required this.queueId,
    required this.liquidationJobId,
    required this.documentNumber,
    required this.fiscalYear,
    required this.period,
    required this.countryCode,
    required this.userId,
    required this.email,
    required this.phone,
    required this.firstName,
    required this.surname,
    required this.jobStatus,
    required this.queueStatus,
    required this.fromAddress,
    required this.toAddress,
    required this.amount,
    required this.currencyCode,
    required this.transactionHash,
    required this.explorerUrl,
    required this.attemptCount,
    required this.retryCount,
    required this.errorMessage,
    required this.createdAt,
    required this.signedAt,
    required this.lastAttemptAt,
    required this.recommendedAction,
    required this.actionMessage,
  });

  final String queueId;
  final String liquidationJobId;

  final String? documentNumber;

  final int fiscalYear;
  final int period;

  final String countryCode;

  final String userId;

  final String? email;
  final String? phone;
  final String? firstName;
  final String? surname;

  final String jobStatus;
  final String queueStatus;

  final String? fromAddress;
  final String? toAddress;

  final double amount;
  final String currencyCode;

  final String? transactionHash;
  final String? explorerUrl;

  final int attemptCount;
  final int retryCount;

  final String? errorMessage;

  final DateTime? createdAt;
  final DateTime? signedAt;
  final DateTime? lastAttemptAt;

  final ManualReviewAction recommendedAction;

  final String actionMessage;

  factory ManualReviewLiquidationRow.fromJson(Map<String, dynamic> json) {
    return ManualReviewLiquidationRow(
      queueId: _string(json['queue_id']),
      liquidationJobId: _string(json['liquidation_job_id']),
      documentNumber: _nullableString(json['document_number']),
      fiscalYear: NumberConversionService.toInt(json['fiscal_year']),
      period: NumberConversionService.toInt(json['period']),
      countryCode: _string(json['country_code']).toLowerCase(),
      userId: _string(json['user_id']),
      email: _nullableString(json['email']),
      phone: _nullableString(json['phone']),
      firstName: _nullableString(json['first_name']),
      surname: _nullableString(json['surname']),
      jobStatus: _string(json['job_status']).toLowerCase(),
      queueStatus: _string(json['queue_status']).toLowerCase(),
      fromAddress: _nullableString(json['from_address']),
      toAddress: _nullableString(json['to_address']),
      amount: NumberConversionService.toDouble(json['amount']),
      currencyCode: _string(json['currency_code']).toLowerCase(),
      transactionHash: _nullableString(json['tx_hash']),
      explorerUrl: _nullableString(json['explorer_url']),
      attemptCount: NumberConversionService.toInt(json['attempt_count']),
      retryCount: NumberConversionService.toInt(json['retry_count']),
      errorMessage: _nullableString(json['error_message']),
      createdAt: _dateTime(json['created_at']),
      signedAt: _dateTime(json['signed_at']),
      lastAttemptAt: _dateTime(json['last_attempt_at']),
      recommendedAction: ManualReviewAction.fromCode(
        json['recommended_action'],
      ),
      actionMessage: _string(json['action_message']),
    );
  }

  String get borrowerName {
    final names = <String>[?firstName, ?surname];

    if (names.isNotEmpty) {
      return names.join(' ');
    }

    return email ?? phone ?? userId;
  }

  bool get hasTransactionHash => transactionHash != null;
}

class ManualReviewLiquidations {
  ManualReviewLiquidations({
    required List<ManualReviewLiquidationRow> rows,
    required this.pagination,
  }) : rows = List.unmodifiable(rows);

  final List<ManualReviewLiquidationRow> rows;

  final ReportPagination pagination;

  factory ManualReviewLiquidations.fromJson(Map<String, dynamic> json) {
    return ManualReviewLiquidations(
      rows: _rows(
        json['rows'],
      ).map(ManualReviewLiquidationRow.fromJson).toList(),
      pagination: ReportPagination.fromJson(_map(json['pagination'])),
    );
  }

  factory ManualReviewLiquidations.empty() {
    return ManualReviewLiquidations(
      rows: const [],
      pagination: ReportPagination.empty(),
    );
  }

  bool get isEmpty => rows.isEmpty;

  bool get isNotEmpty => rows.isNotEmpty;

  int get jobCount => rows.length;

  int countForAction(ManualReviewAction action) {
    return rows.where((row) => row.recommendedAction == action).length;
  }
}

class LiquidationReviewDocument {
  const LiquidationReviewDocument({
    required this.documentNumber,
    required this.fiscalYear,
    required this.period,
    required this.countryCode,
  });

  final String? documentNumber;

  final int fiscalYear;
  final int period;

  final String countryCode;

  factory LiquidationReviewDocument.fromJson(Map<String, dynamic> json) {
    return LiquidationReviewDocument(
      documentNumber: _nullableString(json['document_number']),
      fiscalYear: NumberConversionService.toInt(json['fiscal_year']),
      period: NumberConversionService.toInt(json['period']),
      countryCode: _string(json['country_code']).toLowerCase(),
    );
  }
}

class LiquidationReviewCustomer {
  const LiquidationReviewCustomer({
    required this.userId,
    required this.email,
    required this.phone,
    required this.firstName,
    required this.surname,
  });

  final String userId;

  final String? email;
  final String? phone;
  final String? firstName;
  final String? surname;

  factory LiquidationReviewCustomer.fromJson(Map<String, dynamic> json) {
    return LiquidationReviewCustomer(
      userId: _string(json['user_id']),
      email: _nullableString(json['email']),
      phone: _nullableString(json['phone']),
      firstName: _nullableString(json['first_name']),
      surname: _nullableString(json['surname']),
    );
  }

  String get displayName {
    final names = <String>[
      if (firstName != null) firstName!,
      if (surname != null) surname!,
    ];

    if (names.isNotEmpty) {
      return names.join(' ');
    }

    return email ?? phone ?? userId;
  }
}

class LiquidationReviewStatus {
  const LiquidationReviewStatus({
    required this.jobStatus,
    required this.queueStatus,
    required this.jobError,
    required this.queueError,
    required this.attemptCount,
    required this.retryCount,
  });

  final String jobStatus;
  final String queueStatus;

  final String? jobError;
  final String? queueError;

  final int attemptCount;
  final int retryCount;

  factory LiquidationReviewStatus.fromJson(Map<String, dynamic> json) {
    return LiquidationReviewStatus(
      jobStatus: _string(json['job_status']).toLowerCase(),
      queueStatus: _string(json['queue_status']).toLowerCase(),
      jobError: _nullableString(json['job_error']),
      queueError: _nullableString(json['queue_error']),
      attemptCount: NumberConversionService.toInt(json['attempt_count']),
      retryCount: NumberConversionService.toInt(json['retry_count']),
    );
  }

  bool get hasError => jobError != null || queueError != null;

  bool get hasRetried => retryCount > 0;
}

class ExpectedLiquidationTransfer {
  const ExpectedLiquidationTransfer({
    required this.chain,
    required this.transactionType,
    required this.fromAddress,
    required this.toAddress,
    required this.currencyCode,
    required this.amount,
    required this.rawAmount,
    required this.permitOwner,
    required this.permitNonce,
    required this.permitDeadline,
    required this.permitExpired,
  });

  final String chain;
  final String transactionType;

  final String? fromAddress;
  final String? toAddress;

  final String currencyCode;

  final double amount;

  /// Blockchain integer amount.
  ///
  /// Kept as a string so it never passes
  /// through floating-point conversion.
  final String? rawAmount;

  final String? permitOwner;
  final String? permitNonce;

  final DateTime? permitDeadline;

  final bool? permitExpired;

  factory ExpectedLiquidationTransfer.fromJson(Map<String, dynamic> json) {
    return ExpectedLiquidationTransfer(
      chain: _string(json['chain']).toLowerCase(),
      transactionType: _string(json['transaction_type']).toLowerCase(),
      fromAddress: _nullableString(json['from']),
      toAddress: _nullableString(json['to']),
      currencyCode: _string(json['currency_code']).toLowerCase(),
      amount: NumberConversionService.toDouble(json['amount']),
      rawAmount: _nullableString(json['raw_amount']),
      permitOwner: _nullableString(json['permit_owner']),
      permitNonce: _nullableString(json['permit_nonce']),
      permitDeadline: _dateTime(json['permit_deadline']),
      permitExpired: _nullableBool(json['permit_expired']),
    );
  }
}

class LiquidationReviewValues {
  const LiquidationReviewValues({
    required this.principal,
    required this.interest,
    required this.totalDebt,
    required this.repaymentRequired,
    required this.penaltyAmount,
    required this.totalProceeds,
    required this.collateralRequired,
    required this.goldPrice,
  });

  final double principal;
  final double interest;
  final double totalDebt;

  final double repaymentRequired;
  final double penaltyAmount;
  final double totalProceeds;

  final double collateralRequired;
  final double goldPrice;

  factory LiquidationReviewValues.fromJson(Map<String, dynamic> json) {
    return LiquidationReviewValues(
      principal: NumberConversionService.toDouble(json['principal']),
      interest: NumberConversionService.toDouble(json['interest']),
      totalDebt: NumberConversionService.toDouble(json['total_debt']),
      repaymentRequired: NumberConversionService.toDouble(
        json['repayment_required'],
      ),
      penaltyAmount: NumberConversionService.toDouble(json['penalty_amount']),
      totalProceeds: NumberConversionService.toDouble(json['total_proceeds']),
      collateralRequired: NumberConversionService.toDouble(
        json['collateral_required'],
      ),
      goldPrice: NumberConversionService.toDouble(json['gold_price']),
    );
  }
}

class LiquidationBlockchainEvidence {
  const LiquidationBlockchainEvidence({
    required this.queueTransactionHash,
    required this.recordedTransactionHash,
    required this.blockchainTransactionId,
    required this.transactionStatus,
    required this.chainStatus,
    required this.explorerUrl,
    required this.submittedAt,
    required this.confirmedAt,
    required this.recordedAt,
  });

  final String? queueTransactionHash;
  final String? recordedTransactionHash;

  final String? blockchainTransactionId;

  final String? transactionStatus;
  final String? chainStatus;

  final String? explorerUrl;

  final DateTime? submittedAt;
  final DateTime? confirmedAt;
  final DateTime? recordedAt;

  factory LiquidationBlockchainEvidence.fromJson(Map<String, dynamic> json) {
    return LiquidationBlockchainEvidence(
      queueTransactionHash: _nullableString(json['queue_tx_hash']),
      recordedTransactionHash: _nullableString(json['recorded_tx_hash']),
      blockchainTransactionId: _nullableString(
        json['blockchain_transaction_id'],
      ),
      transactionStatus: _nullableString(
        json['transaction_status'],
      )?.toLowerCase(),
      chainStatus: _nullableString(json['chain_status'])?.toLowerCase(),
      explorerUrl: _nullableString(json['explorer_url']),
      submittedAt: _dateTime(json['submitted_at']),
      confirmedAt: _dateTime(json['confirmed_at']),
      recordedAt: _dateTime(json['recorded_at']),
    );
  }

  bool get hasTransactionHash =>
      queueTransactionHash != null || recordedTransactionHash != null;
}

class LiquidationReviewTimeline {
  const LiquidationReviewTimeline({
    required this.createdAt,
    required this.processingStartedAt,
    required this.lastAttemptAt,
    required this.signedAt,
    required this.claimedAt,
  });

  final DateTime? createdAt;
  final DateTime? processingStartedAt;
  final DateTime? lastAttemptAt;
  final DateTime? signedAt;
  final DateTime? claimedAt;

  factory LiquidationReviewTimeline.fromJson(Map<String, dynamic> json) {
    return LiquidationReviewTimeline(
      createdAt: _dateTime(json['created_at']),
      processingStartedAt: _dateTime(json['processing_started_at']),
      lastAttemptAt: _dateTime(json['last_attempt_at']),
      signedAt: _dateTime(json['signed_at']),
      claimedAt: _dateTime(json['claimed_at']),
    );
  }
}

class LiquidationRecommendedAction {
  const LiquidationRecommendedAction({
    required this.action,
    required this.message,
    required this.successResult,
    required this.notFoundResult,
    required this.uncertainResult,
  });

  final ManualReviewAction action;

  final String message;

  final String? successResult;
  final String? notFoundResult;
  final String? uncertainResult;

  factory LiquidationRecommendedAction.fromJson(Map<String, dynamic> json) {
    return LiquidationRecommendedAction(
      action: ManualReviewAction.fromCode(json['code']),
      message: _string(json['message']),
      successResult: _nullableString(json['success_result']),
      notFoundResult: _nullableString(json['not_found_result']),
      uncertainResult: _nullableString(json['uncertain_result']),
    );
  }
}

class ManualReviewLiquidationDetail {
  ManualReviewLiquidationDetail({
    required this.queueId,
    required this.liquidationJobId,
    required this.manualReviewRequired,
    required this.document,
    required this.customer,
    required this.status,
    required this.expectedTransfer,
    required this.liquidationValues,
    required this.blockchainEvidence,
    required this.timeline,
    required this.recommendedAction,
    required List<String> verificationRequirements,
  }) : verificationRequirements = List.unmodifiable(verificationRequirements);

  final String queueId;
  final String liquidationJobId;

  final bool manualReviewRequired;

  final LiquidationReviewDocument document;
  final LiquidationReviewCustomer customer;
  final LiquidationReviewStatus status;

  final ExpectedLiquidationTransfer expectedTransfer;

  final LiquidationReviewValues liquidationValues;

  final LiquidationBlockchainEvidence blockchainEvidence;

  final LiquidationReviewTimeline timeline;

  final LiquidationRecommendedAction recommendedAction;

  final List<String> verificationRequirements;

  factory ManualReviewLiquidationDetail.fromJson(Map<String, dynamic> json) {
    return ManualReviewLiquidationDetail(
      queueId: _string(json['queue_id']),
      liquidationJobId: _string(json['liquidation_job_id']),
      manualReviewRequired: json['manual_review_required'] == true,
      document: LiquidationReviewDocument.fromJson(_map(json['document'])),
      customer: LiquidationReviewCustomer.fromJson(_map(json['customer'])),
      status: LiquidationReviewStatus.fromJson(_map(json['status'])),
      expectedTransfer: ExpectedLiquidationTransfer.fromJson(
        _map(json['expected_transfer']),
      ),
      liquidationValues: LiquidationReviewValues.fromJson(
        _map(json['liquidation_values']),
      ),
      blockchainEvidence: LiquidationBlockchainEvidence.fromJson(
        _map(json['blockchain_evidence']),
      ),
      timeline: LiquidationReviewTimeline.fromJson(_map(json['timeline'])),
      recommendedAction: LiquidationRecommendedAction.fromJson(
        _map(json['recommended_action']),
      ),
      verificationRequirements: _stringList(json['verification_requirements']),
    );
  }

  bool get requiresOnChainVerification {
    return recommendedAction.action == ManualReviewAction.verifyOnChain ||
        recommendedAction.action == ManualReviewAction.verifyStoredTransaction;
  }

  bool get canResumeAccounting {
    return recommendedAction.action == ManualReviewAction.resumeAccounting;
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

bool? _nullableBool(dynamic value) {
  return value is bool ? value : null;
}

Map<String, dynamic> _map(dynamic value) {
  if (value is! Map) {
    return const {};
  }

  return Map<String, dynamic>.from(value);
}

List<Map<String, dynamic>> _rows(dynamic value) {
  if (value is! List) {
    return const [];
  }

  return value
      .whereType<Map>()
      .map((row) => Map<String, dynamic>.from(row))
      .toList();
}

List<String> _stringList(dynamic value) {
  if (value is! List) {
    return const [];
  }

  return value.map(_nullableString).whereType<String>().toList();
}
