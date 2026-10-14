import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ngoda/data_models/loan/active_loan.dart';
import 'package:ngoda/data_models/params/loan_details_params.dart';
import 'package:ngoda/ui/screens/wallet/loan/service/loan_api_service.dart';
import 'package:ngoda/ui/screens/wallet/loan/service/loan_api_service_provider.dart';
import 'package:ngoda/ui/screens/wallet/loan/state/active_loan_state.dart';

class ActiveLoansNotifier extends Notifier<ActiveLoansState> {
  late final LoanApiService api;

  @override
  ActiveLoansState build() {
    api = ref.read(loanApiServiceProvider);

    return const ActiveLoansState();
  }

  Future<void> loadLoans() async {
    state = state.copyWith(isLoading: true, error: null);

    try {
      final loans = await api.fetchActiveLoans();

      state = state.copyWith(isLoading: false, loans: loans, error: null);
    } catch (error) {
      state = state.copyWith(isLoading: false, error: error.toString());
    }
  }

  Future<void> selectLoan(String loanId) async {
    final id = loanId.trim();

    if (id.isEmpty) {
      state = state.copyWith(error: 'Loan ID cannot be empty.');
      return;
    }

    ActiveLoan? selectedLoan;

    for (final loan in state.loans) {
      if (loan.id == id) {
        selectedLoan = loan;
        break;
      }
    }

    if (selectedLoan == null) {
      state = state.copyWith(
        selectedLoan: null,
        details: null,
        isLoading: false,
        error: 'Loan not found.',
      );
      return;
    }

    state = state.copyWith(
      selectedLoan: selectedLoan,
      details: null,
      isLoading: true,
      error: null,
    );

    try {
      final params = LoanDetailsParams(loanId: id);

      final details = await api.fetchLoanEntries(params);

      state = state.copyWith(isLoading: false, details: details, error: null);
    } catch (error) {
      state = state.copyWith(
        isLoading: false,
        details: null,
        error: error.toString(),
      );
    }
  }

  void clearSelection() {
    state = state.copyWith(
      selectedLoan: null,
      details: null,
      isLoading: false,
      error: null,
    );
  }
}

// import 'package:flutter_riverpod/flutter_riverpod.dart';
// import 'package:ngoda/data_models/loan/active_loan.dart';
// import 'package:ngoda/ui/screens/wallet/loan/service/loan_api_service.dart';
// import 'package:ngoda/ui/screens/wallet/loan/service/loan_api_service_provider.dart';
// import 'package:ngoda/ui/screens/wallet/loan/state/active_loan_state.dart';

// class ActiveLoansNotifier extends Notifier<ActiveLoansState> {
//   late final LoanApiService api;

//   @override
//   ActiveLoansState build() {
//     api = ref.read(loanApiServiceProvider);

//     return const ActiveLoansState();
//   }

//   Future<void> loadLoans() async {
//     state = state.copyWith(isLoading: true, error: null);

//     try {
//       final loans = await api.fetchActiveLoans();

//       state = state.copyWith(isLoading: false, loans: loans, error: null);
//     } catch (error) {
//       state = state.copyWith(isLoading: false, error: error.toString());
//     }
//   }

//   Future<void> selectLoan(String loanId) async {
//     final id = loanId.trim();

//     if (id.isEmpty) {
//       state = state.copyWith(error: 'Loan ID cannot be empty.');

//       return;
//     }

//     ActiveLoan? selectedLoan;

//     for (final loan in state.loans) {
//       if (loan.id == id) {
//         selectedLoan = loan;
//         break;
//       }
//     }

//     if (selectedLoan == null) {
//       state = state.copyWith(
//         selectedLoan: null,
//         details: null,
//         isLoading: false,
//         error: 'Loan not found.',
//       );

//       return;
//     }

//     state = state.copyWith(
//       selectedLoan: selectedLoan,
//       details: null,
//       isLoading: true,
//       error: null,
//     );

//     try {
//       final details = await api.fetchLoanEntries(id);

//       state = state.copyWith(isLoading: false, details: details, error: null);
//     } catch (error) {
//       state = state.copyWith(
//         isLoading: false,
//         details: null,
//         error: error.toString(),
//       );
//     }
//   }

//   void clearSelection() {
//     state = state.copyWith(
//       selectedLoan: null,
//       details: null,
//       isLoading: false,
//       error: null,
//     );
//   }
// }
