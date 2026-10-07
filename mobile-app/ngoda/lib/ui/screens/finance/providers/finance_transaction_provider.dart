import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ngoda/ui/screens/finance/notifier/finance_transaction_notifier.dart';
import 'package:ngoda/ui/screens/finance/state/finance_transaction_state.dart';

final financeTransactionProvider = NotifierProvider<FinanceTransactionNotifier, FinanceTransactionState>(
  FinanceTransactionNotifier.new,
);