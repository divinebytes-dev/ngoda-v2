import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ngoda/ui/screens/wallet/gold/notifier/gold_transaction_notifier.dart';
import 'package:ngoda/ui/screens/wallet/gold/state/gold_transaction_state.dart';

final goldTransactionProvider =
    NotifierProvider<GoldTransactionNotifier, GoldTransactionState>(
      GoldTransactionNotifier.new,
    );
