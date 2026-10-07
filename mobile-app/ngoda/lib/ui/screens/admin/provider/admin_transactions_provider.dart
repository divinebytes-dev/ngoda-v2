import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ngoda/ui/screens/admin/notifier/admin_notifier.dart';
import 'package:ngoda/ui/screens/admin/state/admin_transactions_state.dart';

final adminTransactionsProvider =
    NotifierProvider<AdminNotifier, AdminTransactionsState>(AdminNotifier.new);
