import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ngoda/ui/screens/compliance/notifier/kyc_review_decision_notifier.dart';
import 'package:ngoda/ui/screens/compliance/state/user_kyc_decision_state.dart';

final kycReviewDecisionProvider =
    NotifierProvider<KycReviewDecisionNotifier, KycReviewDecisionState>(
      KycReviewDecisionNotifier.new,
    );
