import 'package:ngoda/services/number_conversion_service.dart';

class PnLAccount {
  const PnLAccount({
    required this.accountCode,
    required this.accountName,
    required this.amount,
  });

  final String accountCode;
  final String accountName;
  final double amount;

  factory PnLAccount.fromJson(Map<String, dynamic> json) {
    return PnLAccount(
      accountCode: json['gl_account_code']?.toString().trim() ?? '',
      accountName: json['gl_account_name']?.toString().trim() ?? '',
      amount: NumberConversionService.toDouble(json['amount']),
    );
  }
}
