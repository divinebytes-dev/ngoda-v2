String getTransactionEdgeFunction(String transactionType) {
  final type = transactionType.trim().toLowerCase();

  switch (type) {
    case 'external_funding':
      return 'external-funding';

    case 'gold_inventory_purchase':
      return 'gold-inventory-purchase';

    default:
      throw ArgumentError.value(
        transactionType,
        'transactionType',
        'NO_FUNCTION_FOR_TRANSACTION',
      );
  }
}
