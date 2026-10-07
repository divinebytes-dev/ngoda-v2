import 'package:flutter/material.dart';

Color getAccountColor(String accountCode) {
  final code = accountCode.trim();

  if (code.isEmpty) {
    return Colors.grey;
  }

  switch (code[0]) {
    case '1':
      return Colors.green;

    case '2':
      return Colors.red;

    case '3':
      return Colors.purple;

    case '4':
      return Colors.blue;

    case '5':
      return Colors.orange;

    default:
      return Colors.grey;
  }
}

Color getEntryColor({required String accountCode, required bool isDebit}) {
  final code = accountCode.trim();

  if (code.isEmpty) {
    return Colors.grey;
  }

  switch (code[0]) {
    case '1':
    case '2':
      return isDebit ? Colors.green : Colors.red;

    case '3':
    case '4':
    case '5':
      return isDebit ? Colors.red : Colors.green;

    default:
      return Colors.grey;
  }
}

Color getEntryColorByAccountName({
  required String accountName,
  required bool isDebit,
}) {
  switch (accountName.trim().toLowerCase()) {
    case 'assets':
    case 'liabilities':
      return isDebit ? Colors.green : Colors.red;

    case 'equity':
    case 'revenue':
    case 'expenses':
      return isDebit ? Colors.red : Colors.green;

    default:
      return Colors.grey;
  }
}
