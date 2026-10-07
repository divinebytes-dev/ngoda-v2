import 'package:ngoda/data_models/common/report_pagination.dart';
import 'package:ngoda/services/number_conversion_service.dart';

class CreditAgentBalanceDrilldown {
  CreditAgentBalanceDrilldown({
    required this.merchant,
    required this.account,
    required this.opening,
    required List<CreditAgentDrilldownEntry> entries,
    required this.pagination,
  }) : entries = List.unmodifiable(entries);

  final CreditAgentDrilldownMerchant merchant;
  final CreditAgentDrilldownAccount account;
  final CreditAgentDrilldownOpening opening;

  final List<CreditAgentDrilldownEntry> entries;

  final ReportPagination pagination;

  factory CreditAgentBalanceDrilldown.fromJson(Map<String, dynamic> json) {
    final rawData = json['data'];

    final data = rawData is Map ? Map<String, dynamic>.from(rawData) : json;

    return CreditAgentBalanceDrilldown(
      merchant: CreditAgentDrilldownMerchant.fromJson(_asMap(data['merchant'])),
      account: CreditAgentDrilldownAccount.fromJson(_asMap(data['account'])),
      opening: CreditAgentDrilldownOpening.fromJson(_asMap(data['opening'])),
      entries: _parseEntries(data['entries']),
      pagination: ReportPagination.fromJson(_asMap(data['pagination'])),
    );
  }

  bool get isEmpty => entries.isEmpty;

  bool get isNotEmpty => entries.isNotEmpty;

  int get currentPage => pagination.page;

  int get totalPages => pagination.totalPages;

  int get totalEntries => pagination.totalEntries;

  bool get hasPrevious => pagination.hasPrevious;

  bool get hasNext => pagination.hasNext;

  static List<CreditAgentDrilldownEntry> _parseEntries(dynamic value) {
    if (value is! List) {
      return const [];
    }

    return value
        .whereType<Map>()
        .map(
          (entry) => CreditAgentDrilldownEntry.fromJson(
            Map<String, dynamic>.from(entry),
          ),
        )
        .toList();
  }
}

class CreditAgentDrilldownMerchant {
  const CreditAgentDrilldownMerchant({
    required this.userId,
    required this.email,
    required this.phone,
    required this.firstName,
    required this.surname,
    required this.address,
    required this.countryCode,
  });

  final String userId;

  final String? email;
  final String? phone;

  final String? firstName;
  final String? surname;

  final String? address;

  final String countryCode;

  factory CreditAgentDrilldownMerchant.fromJson(Map<String, dynamic> json) {
    return CreditAgentDrilldownMerchant(
      userId: _string(json['user_id']),
      email: _nullableString(json['email']),
      phone: _nullableString(json['phone']),
      firstName: _nullableString(json['first_name']),
      surname: _nullableString(json['surname']),
      address: _nullableString(json['address']),
      countryCode: _string(json['country_code']).toLowerCase(),
    );
  }

  String get fullName {
    return <String>[?firstName, ?surname].join(' ');
  }

  String get displayName {
    if (fullName.isNotEmpty) {
      return fullName;
    }

    return email ?? phone ?? userId;
  }

  String get contact {
    return phone ?? email ?? '';
  }
}

class CreditAgentDrilldownAccount {
  const CreditAgentDrilldownAccount({
    required this.creditAgentAccountId,
    required this.currencyCode,
    required this.isActive,
    required this.currentReceivableBalance,
    required this.currentCashHoldingBalance,
  });

  final String creditAgentAccountId;

  final String currencyCode;

  final bool isActive;

  final double currentReceivableBalance;
  final double currentCashHoldingBalance;

  factory CreditAgentDrilldownAccount.fromJson(Map<String, dynamic> json) {
    return CreditAgentDrilldownAccount(
      creditAgentAccountId: _string(json['credit_agent_account_id']),
      currencyCode: _string(json['currency_code']).toLowerCase(),
      isActive: json['is_active'] == true,
      currentReceivableBalance: NumberConversionService.toDouble(
        json['current_receivable_balance'],
      ),
      currentCashHoldingBalance: NumberConversionService.toDouble(
        json['current_cash_holding_balance'],
      ),
    );
  }

  double get totalCurrentBalance {
    return currentReceivableBalance + currentCashHoldingBalance;
  }
}

class CreditAgentDrilldownOpening {
  const CreditAgentDrilldownOpening({
    required this.receivableBalance,
    required this.cashHoldingBalance,
    required this.lastSettlementDocumentNumber,
    required this.lastSettlementAt,
  });

  final double receivableBalance;
  final double cashHoldingBalance;

  final String? lastSettlementDocumentNumber;

  final DateTime? lastSettlementAt;

  factory CreditAgentDrilldownOpening.fromJson(Map<String, dynamic> json) {
    return CreditAgentDrilldownOpening(
      receivableBalance: NumberConversionService.toDouble(
        json['receivable_balance'],
      ),
      cashHoldingBalance: NumberConversionService.toDouble(
        json['cash_holding_balance'],
      ),
      lastSettlementDocumentNumber: _nullableString(
        json['last_settlement_document_number'],
      ),
      lastSettlementAt: _nullableDateTime(json['last_settlement_at']),
    );
  }

  double get totalOpeningBalance {
    return receivableBalance + cashHoldingBalance;
  }

  bool get hasSettlement {
    return lastSettlementDocumentNumber != null;
  }
}

class CreditAgentDrilldownEntry {
  const CreditAgentDrilldownEntry({
    required this.id,
    required this.documentNumber,
    required this.transactionType,
    required this.fiscalYear,
    required this.period,
    required this.currencyCode,
    required this.debitReceivable,
    required this.creditReceivable,
    required this.debitCashHolding,
    required this.creditCashHolding,
    required this.receivableBalanceBefore,
    required this.receivableRunningBalance,
    required this.cashHoldingBalanceBefore,
    required this.cashHoldingRunningBalance,
    required this.createdBy,
    required this.createdAt,
  });

  final String id;
  final String documentNumber;

  /// Dynamic backend transaction type.
  final String transactionType;

  final int fiscalYear;
  final int period;

  final String currencyCode;

  final double debitReceivable;
  final double creditReceivable;

  final double debitCashHolding;
  final double creditCashHolding;

  final double receivableBalanceBefore;
  final double receivableRunningBalance;

  final double cashHoldingBalanceBefore;
  final double cashHoldingRunningBalance;

  final String createdBy;

  final DateTime createdAt;

  factory CreditAgentDrilldownEntry.fromJson(Map<String, dynamic> json) {
    return CreditAgentDrilldownEntry(
      id: _string(json['id']),
      documentNumber: _string(json['document_number']),
      transactionType: _string(json['transaction_type']).toLowerCase(),
      fiscalYear: NumberConversionService.toInt(json['fiscal_year']),
      period: NumberConversionService.toInt(json['period']),
      currencyCode: _string(json['currency_code']).toLowerCase(),
      debitReceivable: NumberConversionService.toDouble(
        json['debit_receivable'],
      ),
      creditReceivable: NumberConversionService.toDouble(
        json['credit_receivable'],
      ),
      debitCashHolding: NumberConversionService.toDouble(
        json['debit_cash_holding'],
      ),
      creditCashHolding: NumberConversionService.toDouble(
        json['credit_cash_holding'],
      ),
      receivableBalanceBefore: NumberConversionService.toDouble(
        json['receivable_balance_before'],
      ),
      receivableRunningBalance: NumberConversionService.toDouble(
        json['receivable_running_balance'],
      ),
      cashHoldingBalanceBefore: NumberConversionService.toDouble(
        json['cash_holding_balance_before'],
      ),
      cashHoldingRunningBalance: NumberConversionService.toDouble(
        json['cash_holding_running_balance'],
      ),
      createdBy: _string(json['created_by']),
      createdAt: _requiredDateTime(json['created_at'], 'created_at'),
    );
  }

  double get receivableMovement {
    return debitReceivable - creditReceivable;
  }

  double get cashHoldingMovement {
    return debitCashHolding - creditCashHolding;
  }

  double get totalBalanceBefore {
    return receivableBalanceBefore + cashHoldingBalanceBefore;
  }

  double get totalRunningBalance {
    return receivableRunningBalance + cashHoldingRunningBalance;
  }

  bool get increasesReceivable => receivableMovement > 0;

  bool get reducesReceivable => receivableMovement < 0;

  bool get increasesCashHolding => cashHoldingMovement > 0;

  bool get reducesCashHolding => cashHoldingMovement < 0;
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

DateTime _requiredDateTime(dynamic value, String field) {
  final raw = _nullableString(value);

  if (raw == null) {
    throw FormatException(
      'CreditAgentBalanceDrilldown.'
      '$field is required.',
    );
  }

  final parsed = DateTime.tryParse(raw);

  if (parsed == null) {
    throw FormatException(
      'CreditAgentBalanceDrilldown.'
      '$field is invalid.',
    );
  }

  return parsed;
}

DateTime? _nullableDateTime(dynamic value) {
  final raw = _nullableString(value);

  if (raw == null) {
    return null;
  }

  return DateTime.tryParse(raw);
}

Map<String, dynamic> _asMap(dynamic value) {
  if (value is Map) {
    return Map<String, dynamic>.from(value);
  }

  return const {};
}
