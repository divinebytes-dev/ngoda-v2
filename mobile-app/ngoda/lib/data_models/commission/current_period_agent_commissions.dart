import 'package:ngoda/data_models/common/report_pagination.dart';
import 'package:ngoda/services/number_conversion_service.dart';

class CurrentPeriodAgentCommissions {
  CurrentPeriodAgentCommissions({
    required this.countryCode,
    required this.fiscalYear,
    required this.period,
    required this.asOf,
    required this.currency,
    required List<CurrentCommissionCurrencyTotal> currencies,
    required List<PendingCommissionItem> items,
    required this.pagination,
  }) : currencies = List.unmodifiable(currencies),
       items = List.unmodifiable(items);

  final String countryCode;
  final int fiscalYear;
  final int period;
  // Keep the exact server timestamp, including fractional-second precision.
  final String asOf;
  final String? currency;
  final List<CurrentCommissionCurrencyTotal> currencies;
  final List<PendingCommissionItem> items;
  final ReportPagination pagination;

  CurrentCommissionCurrencyTotal? get selectedTotal {
    for (final total in currencies) {
      if (total.currencyCode == currency) return total;
    }
    return null;
  }

  List<String> get currencyCodes =>
      List.unmodifiable(currencies.map((row) => row.currencyCode));

  factory CurrentPeriodAgentCommissions.fromJson(Map<String, dynamic> json) {
    final rawData = json['data'];
    final data = rawData is Map ? Map<String, dynamic>.from(rawData) : json;
    final currencies = data['currencies'];
    final items = data['items'];
    final paging = data['pagination'];
    if (currencies is! List || items is! List || paging is! Map) {
      throw const FormatException('Invalid current period commission response');
    }
    final fiscalYear = NumberConversionService.toInt(data['fiscal_year']);
    final period = NumberConversionService.toInt(data['period']);
    final asOf = data['as_of']?.toString() ?? '';
    if (fiscalYear < 1 || period < 1 || period > 12 || DateTime.tryParse(asOf) == null) {
      throw const FormatException('Invalid current period commission period');
    }
    final result = CurrentPeriodAgentCommissions(
      countryCode: _code(data['country_code']),
      fiscalYear: fiscalYear,
      period: period,
      asOf: asOf,
      currency: data['currency'] == null ? null : _code(data['currency']),
      currencies: currencies.map((row) => CurrentCommissionCurrencyTotal.fromJson(_map(row))).toList(),
      items: items.map((row) => PendingCommissionItem.fromJson(_map(row))).toList(),
      pagination: ReportPagination(
        page: NumberConversionService.toInt(paging['page']),
        pageSize: NumberConversionService.toInt(paging['pageSize']),
        totalEntries: NumberConversionService.toInt(paging['totalEntries']),
        totalPages: NumberConversionService.toInt(paging['totalPages']),
        hasPrevious: paging['hasPrevious'] == true,
        hasNext: paging['hasNext'] == true,
      ),
    );
    if (result.pagination.page < 1 || result.pagination.pageSize < 1 ||
        result.pagination.totalPages < 1 || result.pagination.totalEntries < 0 ||
        result.pagination.page > result.pagination.totalPages ||
        result.currencies.map((row) => row.currencyCode).toSet().length != result.currencies.length ||
        (result.currency != null && result.selectedTotal == null) ||
        result.items.any((item) => item.currencyCode != result.currency)) {
      throw const FormatException('Invalid current period commission pagination or currency');
    }
    return result;
  }
}

class CurrentCommissionCurrencyTotal {
  const CurrentCommissionCurrencyTotal({
    required this.currencyCode,
    required this.totalTransactionAmount,
    required this.totalFeeAmount,
    required this.totalCommissionAmount,
    required this.paidCommissionAmount,
    required this.pendingCommissionAmount,
    required this.totalAgents,
    required this.pendingAgents,
    required this.commissionCount,
    required this.paidCount,
    required this.pendingCount,
  });

  final String currencyCode;
  final double totalTransactionAmount;
  final double totalFeeAmount;
  final double totalCommissionAmount;
  final double paidCommissionAmount;
  final double pendingCommissionAmount;
  final int totalAgents;
  final int pendingAgents;
  final int commissionCount;
  final int paidCount;
  final int pendingCount;

  factory CurrentCommissionCurrencyTotal.fromJson(Map<String, dynamic> json) =>
      CurrentCommissionCurrencyTotal(
        currencyCode: _code(json['currency_code']),
        totalTransactionAmount: _amount(json['total_transaction_amount']),
        totalFeeAmount: _amount(json['total_fee_amount']),
        totalCommissionAmount: _amount(json['total_commission_amount']),
        paidCommissionAmount: _amount(json['paid_commission_amount']),
        pendingCommissionAmount: _amount(json['pending_commission_amount']),
        totalAgents: NumberConversionService.toInt(json['total_agents']),
        pendingAgents: NumberConversionService.toInt(json['pending_agents']),
        commissionCount: NumberConversionService.toInt(json['commission_count']),
        paidCount: NumberConversionService.toInt(json['paid_count']),
        pendingCount: NumberConversionService.toInt(json['pending_count']),
      );
}

class PendingCommissionItem {
  const PendingCommissionItem({
    required this.id,
    required this.agentId,
    required this.agentEmail,
    required this.documentNumber,
    required this.reference,
    required this.transactionType,
    required this.currencyCode,
    required this.amount,
    required this.feeAmount,
    required this.commissionRate,
    required this.commissionAmount,
    required this.createdAt,
    required this.settlementBatchId,
  });

  final String id;
  final String agentId;
  final String? agentEmail;
  final String documentNumber;
  final String? reference;
  final String transactionType;
  final String currencyCode;
  final double amount;
  final double feeAmount;
  final double commissionRate;
  final double commissionAmount;
  final DateTime createdAt;
  final String? settlementBatchId;

  String get agentDisplayName => agentEmail ?? agentId;
  String get status => 'pending';

  factory PendingCommissionItem.fromJson(Map<String, dynamic> json) {
    if (json['is_settled'] != false || json['status'] != 'pending') {
      throw const FormatException('Expected a pending commission record');
    }
    return PendingCommissionItem(
      id: _requiredText(json['id']),
      agentId: _requiredText(json['agent_id']),
      agentEmail: _nullableText(json['agent_email']),
      documentNumber: _requiredText(json['document_number']),
      reference: _nullableText(json['reference']),
      transactionType: _code(json['transaction_type']),
      currencyCode: _code(json['currency_code']),
      amount: _amount(json['amount']),
      feeAmount: _amount(json['fee_amount']),
      commissionRate: _amount(json['commission_rate']),
      commissionAmount: _amount(json['commission_amount']),
      createdAt: DateTime.parse(json['created_at'].toString()),
      settlementBatchId: _nullableText(json['settlement_batch_id']),
    );
  }
}

String? _nullableText(dynamic value) {
  final text = value?.toString().trim();
  return text == null || text.isEmpty ? null : text;
}

String _requiredText(dynamic value) {
  final text = _nullableText(value);
  if (text == null) throw const FormatException('Missing commission record field');
  return text;
}

Map<String, dynamic> _map(dynamic value) {
  if (value is! Map) throw const FormatException('Invalid current commission row');
  return Map<String, dynamic>.from(value);
}

String _code(dynamic value) {
  final code = value?.toString().trim().toLowerCase() ?? '';
  if (code.isEmpty) throw const FormatException('Missing current commission code');
  return code;
}

double _amount(dynamic value) {
  final amount = double.tryParse(value?.toString() ?? '');
  if (amount == null || !amount.isFinite || amount < 0) {
    throw const FormatException('Invalid current commission amount');
  }
  return amount;
}
