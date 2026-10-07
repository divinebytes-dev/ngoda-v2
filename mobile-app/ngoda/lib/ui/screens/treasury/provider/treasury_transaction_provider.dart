import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ngoda/ui/screens/treasury/notifier/treasury_transaction_notifier.dart';
import 'package:ngoda/ui/screens/treasury/state/treasury_transaction_state.dart';

final treasuryTransactionProvider =
    NotifierProvider<TreasuryTransactionNotifier, TreasuryTransactionState>(
      TreasuryTransactionNotifier.new,
    );
