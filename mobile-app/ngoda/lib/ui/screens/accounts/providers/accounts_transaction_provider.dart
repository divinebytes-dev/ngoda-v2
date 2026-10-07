import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ngoda/ui/screens/accounts/notifier/accounts_transaction_notifier.dart';
import 'package:ngoda/ui/screens/accounts/state/accounts_transaction_state.dart';

final accountsTransactionProvider =
    NotifierProvider<AccountsTransactionNotifier, AccountsTransactionState>(
      AccountsTransactionNotifier.new,
    );
