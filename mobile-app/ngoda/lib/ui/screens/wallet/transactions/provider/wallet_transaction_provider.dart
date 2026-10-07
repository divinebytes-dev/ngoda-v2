import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ngoda/ui/screens/wallet/transactions/notifier/wallet_transaction_notifier.dart';
import 'package:ngoda/ui/screens/wallet/transactions/state/wallet_transaction_state.dart';

final walletTransactionProvider =
    NotifierProvider<WalletTransactionNotifier, WalletTransactionState>(
      WalletTransactionNotifier.new,
    );
