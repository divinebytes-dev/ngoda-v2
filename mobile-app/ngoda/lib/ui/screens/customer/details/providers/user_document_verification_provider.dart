import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ngoda/ui/screens/customer/details/notifier/user_document_verification.notifier.dart';

import 'package:ngoda/ui/screens/customer/details/state/user_details_transaction_state.dart';

final userDocumentVerificationProvider =
    NotifierProvider<
      UserDocumentVerificationNotifier,
      UserDetailsTransactionState
    >(UserDocumentVerificationNotifier.new);
