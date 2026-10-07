import 'package:ngoda/services/number_conversion_service.dart';

class BalanceSheetAccount {
  const BalanceSheetAccount({
    required this.accountCode,
    required this.accountName,
    required this.balance,
  });

  final String accountCode;
  final String accountName;
  final double balance;

  factory BalanceSheetAccount.fromJson(Map<String, dynamic> json) {
    return BalanceSheetAccount(
      accountCode: json['gl_account_code']?.toString().trim() ?? '',
      accountName: json['gl_account_name']?.toString().trim() ?? '',
      balance: NumberConversionService.toDouble(json['balance']),
    );
  }
}
