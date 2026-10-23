import 'package:ngoda/data_models/common/report_pagination.dart';
import 'package:ngoda/services/number_conversion_service.dart';

class CurrentGovernmentTax {
  CurrentGovernmentTax({
    required this.countryCode,
    required this.fiscalYear,
    required this.period,
    required this.asOf,
    required this.currency,
    required List<CurrentTaxCurrencyTotal> currencies,
    required List<CurrentTaxItem> items,
    required this.pagination,
  }) : currencies = List.unmodifiable(currencies),
       items = List.unmodifiable(items);

  final String countryCode;
  final int fiscalYear;
  final int period;
  // Keep the exact server timestamp, including fractional-second precision.
  final String asOf;
  final String? currency;
  final List<CurrentTaxCurrencyTotal> currencies;
  final List<CurrentTaxItem> items;
  final ReportPagination pagination;

  CurrentTaxCurrencyTotal? get selectedTotal {
    for (final total in currencies) {
      if (total.currencyCode == currency) return total;
    }
    return null;
  }

  List<String> get currencyCodes =>
      List.unmodifiable(currencies.map((row) => row.currencyCode));

  factory CurrentGovernmentTax.fromJson(Map<String, dynamic> json) {
    final rawData = json['data'];
    final data = rawData is Map ? Map<String, dynamic>.from(rawData) : json;
    final currencies = data['currencies'];
    final items = data['items'];
    final paging = data['pagination'];
    if (currencies is! List || items is! List || paging is! Map) {
      throw const FormatException('Invalid current government tax response');
    }
    final fiscalYear = NumberConversionService.toInt(data['fiscal_year']);
    final period = NumberConversionService.toInt(data['period']);
    final asOf = data['as_of']?.toString() ?? '';
    if (fiscalYear < 1 || period < 1 || period > 12 || DateTime.tryParse(asOf) == null) {
      throw const FormatException('Invalid current government tax period');
    }
    final result = CurrentGovernmentTax(
      countryCode: _code(data['country_code']),
      fiscalYear: fiscalYear,
      period: period,
      asOf: asOf,
      currency: data['currency'] == null ? null : _code(data['currency']),
      currencies: currencies.map((row) => CurrentTaxCurrencyTotal.fromJson(_map(row))).toList(),
      items: items.map((row) => CurrentTaxItem.fromJson(_map(row))).toList(),
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
      throw const FormatException('Invalid current government tax pagination or currency');
    }
    return result;
  }
}

class CurrentTaxCurrencyTotal {
  const CurrentTaxCurrencyTotal({
    required this.currencyCode,
    required this.totalGrossAmount,
    required this.totalTaxAmount,
    required this.payableCount,
  });

  final String currencyCode;
  final double totalGrossAmount;
  final double totalTaxAmount;
  final int payableCount;

  factory CurrentTaxCurrencyTotal.fromJson(Map<String, dynamic> json) =>
      CurrentTaxCurrencyTotal(
        currencyCode: _code(json['currency_code']),
        totalGrossAmount: _amount(json['total_gross_amount']),
        totalTaxAmount: _amount(json['total_tax_amount']),
        payableCount: NumberConversionService.toInt(json['payable_count']),
      );
}

class CurrentTaxItem {
  const CurrentTaxItem({
    required this.id,
    required this.documentNumber,
    required this.reference,
    required this.transactionType,
    required this.currencyCode,
    required this.grossAmount,
    required this.taxRate,
    required this.taxAmount,
    required this.createdAt,
  });

  final String id;
  final String documentNumber;
  final String? reference;
  final String transactionType;
  final String currencyCode;
  final double grossAmount;
  final double taxRate;
  final double taxAmount;
  final DateTime createdAt;

  factory CurrentTaxItem.fromJson(Map<String, dynamic> json) => CurrentTaxItem(
    id: json['id'].toString(),
    documentNumber: json['document_number']?.toString() ?? '',
    reference: json['reference']?.toString(),
    transactionType: _code(json['transaction_type']),
    currencyCode: _code(json['currency_code']),
    grossAmount: _amount(json['gross_amount']),
    taxRate: _amount(json['tax_rate']),
    taxAmount: _amount(json['tax_amount']),
    createdAt: DateTime.parse(json['created_at'].toString()),
  );
}

Map<String, dynamic> _map(dynamic value) {
  if (value is! Map) throw const FormatException('Invalid current tax row');
  return Map<String, dynamic>.from(value);
}

String _code(dynamic value) {
  final code = value?.toString().trim().toLowerCase() ?? '';
  if (code.isEmpty) throw const FormatException('Missing current tax code');
  return code;
}

double _amount(dynamic value) {
  final amount = double.tryParse(value?.toString() ?? '');
  if (amount == null || !amount.isFinite || amount < 0) {
    throw const FormatException('Invalid current tax amount');
  }
  return amount;
}
