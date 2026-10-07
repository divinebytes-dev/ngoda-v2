bool isCreditTx(String type) {
  final transactionType = type.trim().toLowerCase();

  if (transactionType.isEmpty) {
    return false;
  }

  if (transactionType == 'external_funding') {
    return true;
  }

  if (transactionType.endsWith('_reversal')) {
    return true;
  }

  return false;
}
