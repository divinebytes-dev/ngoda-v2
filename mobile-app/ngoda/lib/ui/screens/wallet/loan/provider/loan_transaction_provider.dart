import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ngoda/ui/screens/wallet/loan/notifier/loan_transaction_notifier.dart';
import 'package:ngoda/ui/screens/wallet/loan/state/loan_transaction_state.dart';

final loanTransactionProvider =
    NotifierProvider<LoanTransactionNotifier, LoanTransactionState>(
      LoanTransactionNotifier.new,
    );
