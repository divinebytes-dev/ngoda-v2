import 'package:ngoda/ui/enums/enums.dart';

class KycReviewDecisionState {
  final KycReviewDecision? decision;
  final String comments;

  final bool isValid;
  final bool isLoading;
  final bool isSuccess;

  final String? error;

  const KycReviewDecisionState({
    this.decision,
    this.comments = '',
    this.isValid = false,
    this.isLoading = false,
    this.isSuccess = false,
    this.error,
  });

  KycReviewDecisionState copyWith({
    KycReviewDecision? decision,
    String? comments,
    bool? isValid,
    bool? isLoading,
    bool? isSuccess,
    String? error,
    bool clearDecision = false,
    bool clearError = false,
  }) {
    return KycReviewDecisionState(
      decision: clearDecision ? null : decision ?? this.decision,
      comments: comments ?? this.comments,
      isValid: isValid ?? this.isValid,
      isLoading: isLoading ?? this.isLoading,
      isSuccess: isSuccess ?? this.isSuccess,
      error: clearError ? null : error ?? this.error,
    );
  }
}
