import 'package:ngoda/data_models/merchant/credit_agent_currency_balance.dart';
import 'package:ngoda/data_models/common/report_pagination.dart';

class CreditAgentBalanceReport {
  CreditAgentBalanceReport({
    required List<CreditAgentBalanceMerchant> creditAgents,
    required this.pagination,
  }) : creditAgents = List.unmodifiable(creditAgents);

  final List<CreditAgentBalanceMerchant> creditAgents;

  final ReportPagination pagination;

  factory CreditAgentBalanceReport.fromJson(Map<String, dynamic> json) {
    final rawData = json['data'];

    final data = rawData is Map ? Map<String, dynamic>.from(rawData) : json;

    final rawCreditAgents = data['creditAgents'] ?? data['credit_agents'];

    return CreditAgentBalanceReport(
      creditAgents: _parseCreditAgents(rawCreditAgents),
      pagination: ReportPagination.fromJson(_asMap(data['pagination'])),
    );
  }

  factory CreditAgentBalanceReport.empty() {
    return CreditAgentBalanceReport(
      creditAgents: const [],
      pagination: ReportPagination.empty(),
    );
  }

  bool get isEmpty => creditAgents.isEmpty;

  bool get isNotEmpty => creditAgents.isNotEmpty;

  int get page => pagination.page;

  int get pageSize => pagination.pageSize;

  int get totalEntries => pagination.totalEntries;

  int get totalPages => pagination.totalPages;

  bool get hasPrevious => pagination.hasPrevious;

  bool get hasNext => pagination.hasNext;

  CreditAgentBalanceMerchant? getByUserId(String userId) {
    final normalized = userId.trim();

    for (final merchant in creditAgents) {
      if (merchant.userId == normalized) {
        return merchant;
      }
    }

    return null;
  }

  static List<CreditAgentBalanceMerchant> _parseCreditAgents(dynamic value) {
    if (value is! List) {
      return const [];
    }

    return value
        .whereType<Map>()
        .map(
          (merchant) => CreditAgentBalanceMerchant.fromJson(
            Map<String, dynamic>.from(merchant),
          ),
        )
        .toList();
  }
}

class CreditAgentBalanceMerchant {
  const CreditAgentBalanceMerchant({
    required this.userId,
    required this.email,
    required this.phone,
    required this.firstName,
    required this.surname,
    required this.address,
    required this.countryCode,
    required this.status,
    required this.creditAgentWallet,
  });

  final String userId;

  final String? email;
  final String? phone;

  final String? firstName;
  final String? surname;

  final String? address;

  final String countryCode;

  /// Dynamic backend account/user status.
  final String status;

  final CreditAgentWallet creditAgentWallet;

  factory CreditAgentBalanceMerchant.fromJson(Map<String, dynamic> json) {
    return CreditAgentBalanceMerchant(
      userId: _string(json['user_id']),
      email: _nullableString(json['email']),
      phone: _nullableString(json['phone']),
      firstName: _nullableString(json['first_name']),
      surname: _nullableString(json['surname']),
      address: _nullableString(json['residential_address']),
      countryCode: _string(json['country_code']).toLowerCase(),
      status: _string(json['status']).toLowerCase(),
      creditAgentWallet: CreditAgentWallet.fromJson(json),
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

  /*
   * The backend status remains the source
   * of truth.
   *
   * This getter is intentionally derived
   * rather than storing a second boolean
   * that could become inconsistent with
   * status.
   */
  bool get isActive => status == 'active';

  bool get hasCashOwed {
    return creditAgentWallet.currencies.values.any(
      (balance) => balance.hasCashOwed,
    );
  }

  bool get hasReceivableBalance {
    return creditAgentWallet.currencies.values.any(
      (balance) => balance.hasReceivableBalance,
    );
  }

  bool get hasOutstandingBalance {
    return creditAgentWallet.currencies.values.any(
      (balance) => balance.hasOutstandingBalance,
    );
  }

  double get totalCashOwedUsd => creditAgentWallet.totalCashOwedUsd;

  double get totalReceivableUsd => creditAgentWallet.totalReceivableUsd;

  double get totalOutstandingUsd => creditAgentWallet.totalOutstandingUsd;
}

extension CreditAgentBalanceReportX on CreditAgentBalanceReport {
  List<CreditAgentBalanceMerchant> get sortedMerchants {
    final result = [...creditAgents]
      ..sort(
        (first, second) => first.displayName.toLowerCase().compareTo(
          second.displayName.toLowerCase(),
        ),
      );

    return List.unmodifiable(result);
  }

  List<CreditAgentBalanceMerchant> get merchantsWithCashOwed {
    return List.unmodifiable(
      creditAgents.where((merchant) => merchant.hasCashOwed),
    );
  }

  List<CreditAgentBalanceMerchant> get merchantsWithReceivableBalance {
    return List.unmodifiable(
      creditAgents.where((merchant) => merchant.hasReceivableBalance),
    );
  }

  List<CreditAgentBalanceMerchant> get merchantsWithOutstandingBalance {
    return List.unmodifiable(
      creditAgents.where((merchant) => merchant.hasOutstandingBalance),
    );
  }

  double get totalCashOwedUsd {
    return creditAgents.fold(
      0.0,
      (total, merchant) => total + merchant.totalCashOwedUsd,
    );
  }

  double get totalReceivableUsd {
    return creditAgents.fold(
      0.0,
      (total, merchant) => total + merchant.totalReceivableUsd,
    );
  }

  double get totalOutstandingUsd {
    return totalCashOwedUsd + totalReceivableUsd;
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

Map<String, dynamic> _asMap(dynamic value) {
  if (value is Map) {
    return Map<String, dynamic>.from(value);
  }

  return const {};
}
