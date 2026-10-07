import 'package:ngoda/services/number_conversion_service.dart';

class TrialBalanceAccount {
  const TrialBalanceAccount({
    required this.accountCode,
    required this.accountName,
    required this.debit,
    required this.credit,
  });

  final String accountCode;
  final String accountName;

  final double debit;
  final double credit;

  factory TrialBalanceAccount.fromJson(Map<String, dynamic> json) {
    return TrialBalanceAccount(
      accountCode: json['gl_account_code']?.toString().trim() ?? '',
      accountName: json['gl_account_name']?.toString().trim() ?? '',
      debit: NumberConversionService.toDouble(json['total_debit']),
      credit: NumberConversionService.toDouble(json['total_credit']),
    );
  }

  double get difference => debit - credit;

  bool get hasActivity => debit != 0 || credit != 0;
}
