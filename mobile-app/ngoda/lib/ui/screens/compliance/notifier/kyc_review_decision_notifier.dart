import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ngoda/ui/enums/enums.dart';
import 'package:ngoda/ui/screens/compliance/services/compliance_api_service_provider.dart';
import 'package:ngoda/ui/screens/compliance/state/user_kyc_decision_state.dart';

class KycReviewDecisionNotifier extends Notifier<KycReviewDecisionState> {
  @override
  KycReviewDecisionState build() {
    return const KycReviewDecisionState();
  }

  void selectDecision(KycReviewDecision decision) {
    state = state.copyWith(
      decision: decision,
      isValid: _validate(decision: decision, comments: state.comments),
      isSuccess: false,
      clearError: true,
    );
  }

  void updateComments(String value) {
    state = state.copyWith(
      comments: value,
      isValid: _validate(decision: state.decision, comments: value),
      isSuccess: false,
      clearError: true,
    );
  }

  bool _validate({
    required KycReviewDecision? decision,
    required String comments,
  }) {
    if (decision == null) {
      return false;
    }

    if (decision == KycReviewDecision.reject ||
        decision == KycReviewDecision.requestChanges) {
      return comments.trim().isNotEmpty;
    }

    return true;
  }

  Future<void> submitDecision({required String userId}) async {
    final decision = state.decision;
    final comments = state.comments.trim();

    if (decision == null) {
      state = state.copyWith(
        isValid: false,
        isSuccess: false,
        error: 'Please select a review decision',
      );

      return;
    }

    if (!_validate(decision: decision, comments: comments)) {
      state = state.copyWith(
        isValid: false,
        isSuccess: false,
        error: 'Please provide a reason for this decision',
      );

      return;
    }

    state = state.copyWith(isLoading: true, isSuccess: false, clearError: true);

    try {
      final service = ref.read(complianceApiServiceProvider);

      await service.updateUserKyc(
        userId: userId,
        decision: _decisionValue(decision),
        comment: comments.isEmpty ? null : comments,
      );

      state = state.copyWith(
        isLoading: false,
        isSuccess: true,
        isValid: true,
        clearError: true,
      );
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        isSuccess: false,
        error: e.toString(),
      );

      rethrow;
    }
  }

  String _decisionValue(KycReviewDecision decision) {
    switch (decision) {
      case KycReviewDecision.approve:
        return 'approve';

      case KycReviewDecision.requestChanges:
        return 'request_changes';

      case KycReviewDecision.reject:
        return 'reject';
    }
  }

  void reset() {
    state = const KycReviewDecisionState();
  }
}
