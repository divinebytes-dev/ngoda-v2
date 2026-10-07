String formatTxType(String transactionType) {
  final type = transactionType.trim().toLowerCase();

  if (type.isEmpty) {
    return '';
  }

  const reversalSuffix = '_reversal';

  if (type.endsWith(reversalSuffix)) {
    final baseType = type.substring(0, type.length - reversalSuffix.length);

    return '${_formatBaseTransactionType(baseType)} Reversal';
  }

  return _formatBaseTransactionType(type);
}

String _formatBaseTransactionType(String transactionType) {
  switch (transactionType) {
    case 'loan_disbursement':
      return 'SVA Disbursement';

    case 'loan_repayment':
      return 'SVA Repayment';

    case 'loan_liquidation':
      return 'SVA Liquidation';

    default:
      return _titleCaseTransactionType(transactionType);
  }
}

String _titleCaseTransactionType(String transactionType) {
  return transactionType
      .split('_')
      .where((part) => part.isNotEmpty)
      .map(_capitalize)
      .join(' ');
}

String _capitalize(String value) {
  if (value.isEmpty) {
    return value;
  }

  if (value.length == 1) {
    return value.toUpperCase();
  }

  return '${value[0].toUpperCase()}'
      '${value.substring(1)}';
}
