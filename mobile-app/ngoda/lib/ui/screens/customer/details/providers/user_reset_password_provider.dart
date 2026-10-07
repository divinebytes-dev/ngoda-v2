import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ngoda/ui/screens/customer/details/notifier/user_password_reset_notifier.dart';

import 'package:ngoda/ui/screens/customer/details/state/user_details_transaction_state.dart';

final userResetPasswordProvider =
    NotifierProvider<UserResetPasswordNotifier, UserDetailsTransactionState>(
      UserResetPasswordNotifier.new,
    );
