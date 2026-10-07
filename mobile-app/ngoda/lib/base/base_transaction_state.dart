import 'package:ngoda/ui/enums/enums.dart';

abstract class BaseTransactionState {
  final TransactionStatus transactionStatus;
  const BaseTransactionState({required this.transactionStatus});
}
