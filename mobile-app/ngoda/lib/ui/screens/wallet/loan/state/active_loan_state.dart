import 'package:ngoda/data_models/loan/active_loan.dart';
import 'package:ngoda/data_models/loan/loan_detail.dart';

class ActiveLoansState {
  static const _unset = Object();

  final bool isLoading;
  final List<ActiveLoan> loans;
  final ActiveLoan? selectedLoan;
  final LoanDetails? details;
  final String? error;

  const ActiveLoansState({
    this.isLoading = false,
    this.loans = const [],
    this.selectedLoan,
    this.details,
    this.error,
  });

  ActiveLoansState copyWith({
    bool? isLoading,
    List<ActiveLoan>? loans,
    Object? selectedLoan = _unset,
    Object? details = _unset,
    Object? error = _unset,
  }) {
    return ActiveLoansState(
      isLoading: isLoading ?? this.isLoading,
      loans: loans ?? this.loans,
      selectedLoan: identical(selectedLoan, _unset)
          ? this.selectedLoan
          : selectedLoan as ActiveLoan?,
      details: identical(details, _unset)
          ? this.details
          : details as LoanDetails?,
      error: identical(error, _unset) ? this.error : error as String?,
    );
  }
}
