import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ngoda/ui/screens/customer/details/notifier/user_contacts_notifier.dart';

import 'package:ngoda/ui/screens/customer/details/state/user_details_transaction_state.dart';

final userContactsProvider =
    NotifierProvider<UserContactsNotifier, UserDetailsTransactionState>(
      UserContactsNotifier.new,
    );
