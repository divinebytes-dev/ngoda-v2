import 'package:ngoda/data_models/gl/gl_totals.dart';
import 'package:ngoda/data_models/gl/token_gl_account_summary.dart';
import 'package:ngoda/services/number_conversion_service.dart';

class TokenGLSummary {
  TokenGLSummary({
    required this.fiscalYear,
    required this.period,
    required this.currencyCode,
    required this.totals,
    required List<TokenGLAccountSummary> accounts,
  }) : accounts = List.unmodifiable(accounts);

  final int fiscalYear;
  final int period;

  final String currencyCode;

  final GLTotals totals;

  final List<TokenGLAccountSummary> accounts;

  factory TokenGLSummary.fromJson(Map<String, dynamic> json) {
    return TokenGLSummary(
      fiscalYear: NumberConversionService.toInt(json['fiscalYear']),
      period: NumberConversionService.toInt(json['period']),
      currencyCode: json['currency']?.toString().trim().toLowerCase() ?? '',
      totals: GLTotals.fromJson(_asMap(json['totals'])),
      accounts: _parseAccounts(json['accounts']),
    );
  }

  bool get hasAccounts => accounts.isNotEmpty;

  int get accountCount => accounts.length;

  static List<TokenGLAccountSummary> _parseAccounts(dynamic value) {
    if (value is! List) {
      return const [];
    }

    return value
        .whereType<Map>()
        .map(
          (account) => TokenGLAccountSummary.fromJson(
            Map<String, dynamic>.from(account),
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
