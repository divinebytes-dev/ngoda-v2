import 'package:ngoda/services/number_conversion_service.dart';

class TokenGLAccountSummary {
  const TokenGLAccountSummary({
    required this.accountCode,
    required this.description,
    required this.opening,
    required this.debit,
    required this.credit,
    required this.closing,
  });

  final String accountCode;
  final String description;

  final double opening;
  final double debit;
  final double credit;
  final double closing;

  factory TokenGLAccountSummary.fromJson(Map<String, dynamic> json) {
    return TokenGLAccountSummary(
      accountCode: json['gl_account_code']?.toString().trim() ?? '',
      description: json['description']?.toString().trim() ?? '',
      opening: NumberConversionService.toDouble(json['opening_balance']),
      debit: NumberConversionService.toDouble(json['debit']),
      credit: NumberConversionService.toDouble(json['credit']),
      closing: NumberConversionService.toDouble(json['closing_balance']),
    );
  }

  bool get hasActivity => debit != 0 || credit != 0;
}
