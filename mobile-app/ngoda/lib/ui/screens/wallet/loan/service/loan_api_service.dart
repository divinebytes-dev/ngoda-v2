import 'package:ngoda/data_models/gamification/loyalty/transaction_loyalty_result.dart';
import 'package:ngoda/data_models/loan/active_loan.dart';
import 'package:ngoda/data_models/loan/loan_detail.dart';
import 'package:ngoda/data_models/loan/loan_preview.dart';
import 'package:ngoda/data_models/transaction/transaction_data.dart';
import 'package:ngoda/services/supabase_function_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class LoanApiService {
  const LoanApiService(this._functions);

  final SupabaseFunctionService _functions;

  Future<List<ActiveLoan>> fetchActiveLoans() async {
    final data = await _functions.invokeList(
      functionName: 'active-loans',
      method: HttpMethod.get,
      invalidResponseMessage: 'Invalid active loans response',
    );

    return data.map((item) {
      if (item is! Map) {
        throw Exception('Invalid active loan response');
      }

      return ActiveLoan.fromJson(Map<String, dynamic>.from(item));
    }).toList();
  }

  Future<LoanDetails> fetchLoanEntries(String id) async {
    final loanId = id.trim();

    if (loanId.isEmpty) {
      throw ArgumentError.value(id, 'id', 'Loan ID cannot be empty.');
    }

    final data = await _functions.invokeData(
      functionName: 'loan-detail',
      body: {'loan_id': loanId},
      invalidResponseMessage: 'Invalid loan detail response',
    );

    return LoanDetails.fromJson(data);
  }

  Future<DateTime?> getLastAcrual() async {
    final data = await _functions.invokeData(
      functionName: 'loan-interest-accrual-date',
      invalidResponseMessage: 'Invalid loan interest accrual response',
    );

    final rawDate = data['last_accrual_run'];

    if (rawDate == null) {
      return null;
    }

    if (rawDate is! String) {
      throw Exception('Invalid loan interest accrual date');
    }

    final date = DateTime.tryParse(rawDate);

    if (date == null) {
      throw Exception('Invalid loan interest accrual date');
    }

    return date;
  }

  Future<LoanPreview> loanPreview({required double amount}) async {
    if (!amount.isFinite || amount <= 0) {
      throw ArgumentError.value(
        amount,
        'amount',
        'Loan amount must be greater than zero.',
      );
    }

    final data = await _functions.invokeData(
      functionName: 'loan-preview',
      body: {'required_amount': amount},
      invalidResponseMessage: 'Invalid loan preview response',
    );

    /*
     * Preserve the current loan-preview
     * backend contract.
     *
     * The function response contains the
     * preview under a nested "data" property.
     */
    final raw = data['data'];

    if (raw is! Map) {
      throw Exception('Invalid loan preview response');
    }

    return LoanPreview.fromJson(Map<String, dynamic>.from(raw));
  }

  Future<TransactionLoyaltyResult> repay({
    required double amount,
    required String reference,
  }) async {
    if (!amount.isFinite || amount <= 0) {
      throw ArgumentError.value(
        amount,
        'amount',
        'Repayment amount must be greater than zero.',
      );
    }

    final transactionReference = _requiredReference(reference);

    final data = await _functions.invokeData(
      functionName: 'loan-repayment',
      body: {'amount': amount, 'reference': transactionReference},
      invalidResponseMessage: 'Invalid loan repayment response',
    );

    final loyalty = data['loyalty'];

    if (loyalty is! Map) {
      throw Exception('Invalid loan repayment loyalty response');
    }

    return TransactionLoyaltyResult.fromJson(
      Map<String, dynamic>.from(loyalty),
    );
  }

  Future<void> borrow({
    required double amount,
    required String reference,
  }) async {
    if (!amount.isFinite || amount <= 0) {
      throw ArgumentError.value(
        amount,
        'amount',
        'Loan amount must be greater than zero.',
      );
    }

    final transactionReference = _requiredReference(reference);

    await _functions.invokeVoid(
      functionName: 'loan-disbursement',
      body: {'required_amount': amount, 'reference': transactionReference},
    );
  }

  Future<void> topupCollateral({
    required TransactionData transactionData,
  }) async {
    await _functions.invokeVoid(
      functionName: 'topup-collateral',
      body: {'transaction': transactionData},
    );
  }

  String _requiredReference(String reference) {
    final value = reference.trim();

    if (value.isEmpty) {
      throw ArgumentError.value(
        reference,
        'reference',
        'Reference cannot be empty.',
      );
    }

    return value;
  }
}
