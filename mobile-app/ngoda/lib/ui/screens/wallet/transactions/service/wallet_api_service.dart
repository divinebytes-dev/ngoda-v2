import 'package:ngoda/data_models/fee/cash_transfer_fee_configuration.dart';
import 'package:ngoda/data_models/gamification/loyalty/transaction_loyalty_result.dart';
import 'package:ngoda/data_models/payment/max_tap_payment_amount_list.dart';
import 'package:ngoda/data_models/transaction/sender_approval.dart';
import 'package:ngoda/data_models/transaction/transaction_data.dart';
import 'package:ngoda/services/supabase_function_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class WalletApiService {
  WalletApiService(this._functions);

  final SupabaseFunctionService _functions;

  Future<TransactionLoyaltyResult> cashDeposit({
    required TransactionData transaction,
    required SenderApproval approval,
  }) async {
    final data = await _functions.invokeData(
      functionName: 'cash-deposit',
      body: {
        'transaction': transaction.toJson(),
        'approval': approval.toJson(),
      },
      invalidResponseMessage: 'Invalid cash deposit response',
    );

    return _readLoyaltyResult(
      data,
      invalidResponseMessage: 'Invalid cash deposit loyalty response',
    );
  }

  Future<void> creditAgentCashSettlement({
    required TransactionData transaction,
    required SenderApproval approval,
  }) async {
    await _functions.invokeVoid(
      functionName: 'credit-agent-cash-settlement',
      body: {
        'transaction': transaction.toJson(),
        'approval': approval.toJson(),
      },
    );
  }

  Future<TransactionLoyaltyResult> creditAgentCashDeposit({
    required TransactionData transaction,
    required SenderApproval approval,
  }) async {
    final data = await _functions.invokeData(
      functionName: 'credit-agent-cash-deposit',
      body: {
        'transaction': transaction.toJson(),
        'approval': approval.toJson(),
      },
      invalidResponseMessage: 'Invalid credit agent cash deposit response',
    );

    return _readLoyaltyResult(
      data,
      invalidResponseMessage:
          'Invalid credit agent cash deposit loyalty response',
    );
  }

  Future<TransactionLoyaltyResult> cashTransfer({
    required TransactionData transaction,
    required String feePaymentMethod,
  }) async {
    final data = await _functions.invokeData(
      functionName: 'cash-transfer',
      body: {
        'transaction': transaction.toJson(),
        'fee_payment_method': feePaymentMethod,
      },
      invalidResponseMessage: 'Invalid cash transfer response',
    );

    return _readLoyaltyResult(
      data,
      invalidResponseMessage: 'Invalid cash transfer loyalty response',
    );
  }

  Future<void> processUserWithdrawal(
    TransactionData transaction,
    SenderApproval approval,
  ) async {
    await _functions.invokeVoid(
      functionName: 'cash-withdrawal',
      body: {
        'transaction': transaction.toJson(),
        'approval': approval.toJson(),
      },
    );
  }

  Future<void> creditAgentProcessUserWithdrawal(
    TransactionData transaction,
    SenderApproval approval,
  ) async {
    await _functions.invokeVoid(
      functionName: 'credit-agent-cash-withdrawal',
      body: {
        'transaction': transaction.toJson(),
        'approval': approval.toJson(),
      },
    );
  }

  Future<void> merchantVoucherPayment({
    required TransactionData transaction,
    required TransactionData voucher,
  }) async {
    await _functions.invokeVoid(
      functionName: 'voucher-payment',
      body: {'transaction': transaction.toJson(), 'voucher': voucher.toJson()},
    );
  }

  Future<TransactionLoyaltyResult> merchantPayment({
    required TransactionData paymentData,
    required SenderApproval approval,
    required bool paymentFeeContribution,
  }) async {
    final data = await _functions.invokeData(
      functionName: 'merchant-payment',
      body: {
        'transaction': paymentData.toJson(),
        'approval': approval.toJson(),
        'payment_fee_contribution': paymentFeeContribution,
      },
      invalidResponseMessage: 'Invalid merchant payment response',
    );

    return _readLoyaltyResult(
      data,
      invalidResponseMessage: 'Invalid merchant payment loyalty response',
    );
  }

  Future<MaxTapPaymentAmountList> getMaximumTapPaymentAmount() async {
    final data = await _functions.invokeList(
      functionName: 'express-tap-limits',
      invalidResponseMessage: 'Invalid maximum tap payment amount response',
    );

    return MaxTapPaymentAmountList.fromJson(data);
  }

  Future<CashTransferFeeConfiguration> fetchConfiguration() async {
    final data = await _functions.invokeData(
      functionName: 'fetch-cash-transfer-fee-configuration',
      method: HttpMethod.get,
      invalidResponseMessage:
          'Invalid cash transfer fee configuration response',
    );

    return CashTransferFeeConfiguration.fromJson(data);
  }

  TransactionLoyaltyResult _readLoyaltyResult(
    Map<String, dynamic> data, {
    required String invalidResponseMessage,
  }) {
    final loyalty = data['loyalty'];

    if (loyalty is! Map) {
      throw Exception(invalidResponseMessage);
    }

    return TransactionLoyaltyResult.fromJson(
      Map<String, dynamic>.from(loyalty),
    );
  }
}
