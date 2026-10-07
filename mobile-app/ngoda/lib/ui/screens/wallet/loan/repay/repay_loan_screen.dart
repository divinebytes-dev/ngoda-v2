import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:ngoda/data_models/payment/payment_row.dart';
import 'package:ngoda/services/dialog_service.dart';
import 'package:ngoda/services/number_format_service.dart';
import 'package:ngoda/services/transaction_loyalty_celebration_service.dart';
import 'package:ngoda/ui/enums/enums.dart';
import 'package:ngoda/ui/extensions/app_size.dart';
import 'package:ngoda/ui/extensions/theme_extension.dart';
import 'package:ngoda/ui/functions/refresh_user_dashboard.dart';
import 'package:ngoda/ui/screens/wallet/loan/provider/loan_transaction_provider.dart';
import 'package:ngoda/ui/screens/wallet/loan/state/loan_transaction_state.dart';
import 'package:ngoda/ui/screens/wallet/transactions/provider/customer_transaction_setup_provider.dart';
import 'package:ngoda/ui/shared/app_text_styles.dart';
import 'package:ngoda/ui/widgets/app_button.dart';
import 'package:ngoda/ui/widgets/app_error_state.dart';
import 'package:ngoda/ui/widgets/app_loader.dart';
import 'package:ngoda/ui/widgets/app_value_row.dart';
import 'package:ngoda/ui/widgets/input_field.dart';
import 'package:ngoda/ui/widgets/payment_calculation_card.dart';
import 'package:ngoda/ui/widgets/view_header.dart';

class RepayLoanScreen extends ConsumerStatefulWidget {
  const RepayLoanScreen({super.key});

  @override
  ConsumerState<RepayLoanScreen> createState() => _RepayLoanScreenState();
}

class _RepayLoanScreenState extends ConsumerState<RepayLoanScreen> {
  final TextEditingController amountController = TextEditingController();

  bool _initialized = false;

  @override
  void dispose() {
    amountController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;

    final dashboardAsync = ref.watch(customerTransactionSetupProvider);

    final state = ref.watch(loanTransactionProvider);

    return Scaffold(
      body: SafeArea(
        child: GestureDetector(
          onTap: () => FocusScope.of(context).unfocus(),
          child: Padding(
            padding: EdgeInsets.all(spacing.lg),
            child: dashboardAsync.when(
              loading: () => const AppLoader(),

              error: (error, _) => AppErrorState(
                message: error.toString(),
                onAction: () => context.pop(),
              ),

              data: (transactionSetup) {
                final loanSummary = transactionSetup.loanSummary;

                final availableBalance = transactionSetup.balances['usd'] ?? 0;

                _initializeTransaction(
                  principalBalance: loanSummary.principalOutstanding,
                  interestBalance: loanSummary.interestOutstanding,
                );

                return SingleChildScrollView(
                  child: Column(
                    children: [
                      ViewHeader(
                        title: 'Settle Access Balance',
                        subtitle: 'Liquidity fee will be paid first',
                        onClose: () => _close(context),
                      ),

                      SizedBox(height: spacing.lg),

                      _SettlementCard(
                        amountController: amountController,
                        availableBalance: availableBalance,
                        state: state,
                        onAmountChanged: (amount) {
                          ref
                              .read(loanTransactionProvider.notifier)
                              .updateRepayAmount(
                                amount,
                                balance: availableBalance,
                              );
                        },
                        onMax: () => _setMaximum(availableBalance),
                        onCancel: () => _close(context),
                        onSettle: _handleRepay,
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  void _initializeTransaction({
    required double principalBalance,
    required double interestBalance,
  }) {
    if (_initialized) {
      return;
    }

    _initialized = true;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }

      final notifier = ref.read(loanTransactionProvider.notifier);

      notifier.reset();

      notifier.init(
        principalBalance: principalBalance,
        interestBalance: interestBalance,
      );
    });
  }

  void _setMaximum(double availableBalance) {
    final state = ref.read(loanTransactionProvider);

    final loanBalance = state.totalBalance;

    final maximum = availableBalance < loanBalance
        ? availableBalance
        : loanBalance;

    amountController.text = maximum.toStringAsFixed(2);

    amountController.selection = TextSelection.fromPosition(
      TextPosition(offset: amountController.text.length),
    );

    ref
        .read(loanTransactionProvider.notifier)
        .updateRepayAmount(maximum, balance: availableBalance);
  }

  void _close(BuildContext context) {
    amountController.clear();

    ref.read(loanTransactionProvider.notifier).reset();

    context.pop();
  }

  Future<void> _handleRepay() async {
    final notifier = ref.read(loanTransactionProvider.notifier);

    try {
      final confirmed = await _confirmLoanRepayment();

      if (confirmed != true) {
        return;
      }

      await notifier.repayLoan();

      final loyaltyResult = ref.read(loanTransactionProvider).loyaltyResult;

      if (!mounted) {
        return;
      }

      await _showReceipt();

      if (!mounted) {
        return;
      }

      notifier.reset();
      amountController.clear();

      context.pop();
      refreshUserDashboard(ref);

      await TransactionLoyaltyCelebrationService.show(context, loyaltyResult);
    } catch (error) {
      if (!mounted) {
        return;
      }

      await DialogService.error(context, message: error.toString());
    }
  }

  Future<bool?> _confirmLoanRepayment() {
    final state = ref.read(loanTransactionProvider);

    return DialogService.paymentConfirmation(
      context,
      title: 'Confirm Balance Settlement',
      rows: [
        PaymentRow(
          'Liquidity Fee Paid',
          NumberFormatService.formatAmount(state.interestPaid, decimals: 2),
          type: PaymentRowType.amount,
        ),
        PaymentRow(
          'Access Balance Paid',
          NumberFormatService.formatAmount(state.principalPaid, decimals: 2),
          type: PaymentRowType.amount,
        ),
        PaymentRow(
          'Total Paid',
          NumberFormatService.formatAmount(state.amount, decimals: 2),
          type: PaymentRowType.amount,
          isBold: true,
        ),
      ],
    );
  }

  Future<void> _showReceipt() async {
    final state = ref.read(loanTransactionProvider);

    final receiptClosed = Completer<void>();

    await DialogService.paymentReceipt(
      context,
      title: 'Balance Settlement Successful',
      rows: [
        PaymentRow(
          'Liquidity Fee Paid',
          NumberFormatService.formatAmount(state.interestPaid, decimals: 2),
          type: PaymentRowType.amount,
        ),
        PaymentRow(
          'Access Balance Paid',
          NumberFormatService.formatAmount(state.principalPaid, decimals: 2),
          type: PaymentRowType.amount,
        ),
        PaymentRow(
          'Total Paid',
          NumberFormatService.formatAmount(state.amount, decimals: 2),
          type: PaymentRowType.amount,
          isBold: true,
        ),
      ],
      onDone: () {
        if (!receiptClosed.isCompleted) {
          receiptClosed.complete();
        }
      },
    );

    await receiptClosed.future;

    await WidgetsBinding.instance.endOfFrame;
  }
}

class _SettlementCard extends StatelessWidget {
  const _SettlementCard({
    required this.amountController,
    required this.availableBalance,
    required this.state,
    required this.onAmountChanged,
    required this.onMax,
    required this.onCancel,
    required this.onSettle,
  });

  final TextEditingController amountController;

  final double availableBalance;

  final LoanTransactionState state;

  final ValueChanged<double> onAmountChanged;

  final VoidCallback onMax;
  final VoidCallback onCancel;

  final Future<void> Function() onSettle;

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: spacing.sm,
        vertical: spacing.md,
      ),
      decoration: BoxDecoration(
        color: context.theme.cardColor,
        borderRadius: BorderRadius.circular(context.radius.cardRadius),
        border: Border.all(
          color: context.colorScheme.outlineVariant.withValues(alpha: 0.09),
        ),
      ),
      child: Column(
        children: [
          InputField(
            controller: amountController,
            placeholder: 'Amount',
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            onChanged: (value) {
              final amount = NumberFormatService.anyToDouble(value.trim());

              onAmountChanged(amount);
            },
            suffixIcon: Padding(
              padding: EdgeInsets.symmetric(horizontal: spacing.md),
              child: GestureDetector(
                onTap: onMax,
                child: Align(
                  alignment: Alignment.center,
                  widthFactor: 1,
                  child: Text(
                    'Max',
                    style: AppTextStyles.small(context).copyWith(
                      color: Theme.of(context).colorScheme.primary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ),
          ),
          SizedBox(height: spacing.md),
          _AvailableBalance(balance: availableBalance),
          if (state.amount > 0) ...[
            SizedBox(height: spacing.lg),
            _RepaymentCalculation(state: state),
          ],
          SizedBox(height: spacing.lg),
          Row(
            children: [
              Expanded(
                child: AppButton(
                  text: 'Cancel',
                  isPrimary: false,
                  isDisabled: state.isLoading,
                  onPressed: onCancel,
                ),
              ),
              SizedBox(width: spacing.md),
              Expanded(
                child: AppButton(
                  text: 'Settle',
                  isProcessing: state.isLoading,
                  onPressed: !state.isValid || state.isLoading
                      ? null
                      : onSettle,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _AvailableBalance extends StatelessWidget {
  const _AvailableBalance({required this.balance});

  final double balance;

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;

    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(spacing.md),
      decoration: BoxDecoration(
        color: context.theme.cardColor.withValues(alpha: 0.25),
        borderRadius: BorderRadius.circular(context.radius.md),
      ),
      child: AppValueRow(
        label: 'Available Balance',
        value: NumberFormatService.formatAmount(balance, decimals: 2),
      ),
    );
  }
}

class _RepaymentCalculation extends StatelessWidget {
  const _RepaymentCalculation({required this.state});

  final LoanTransactionState state;

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    final colorScheme = Theme.of(context).colorScheme;

    return PaymentCalculationCard(
      children: [
        AppValueRow(
          label: 'Liquidity Fee Balance',
          value: NumberFormatService.formatAmount(
            state.interestBalance,
            decimals: 2,
          ),
        ),

        SizedBox(height: spacing.sm),

        AppValueRow(
          label: 'Access Balance',
          value: NumberFormatService.formatAmount(
            state.principalBalance,
            decimals: 2,
          ),
        ),

        Divider(height: spacing.lg),

        AppValueRow(
          label: 'Liquidity Fee Paid',
          value: NumberFormatService.formatAmount(
            state.interestPaid,
            decimals: 2,
          ),
        ),

        SizedBox(height: spacing.sm),

        AppValueRow(
          label: 'Access Balance Paid',
          value: NumberFormatService.formatAmount(
            state.principalPaid,
            decimals: 2,
          ),
        ),

        Divider(height: spacing.lg),

        AppValueRow(
          label: 'Liquidity Fee Remaining',
          value: NumberFormatService.formatAmount(
            state.remainingInterest,
            decimals: 2,
          ),
          valueColor: state.remainingInterest == 0
              ? Colors.green
              : Colors.orange,
        ),

        SizedBox(height: spacing.sm),

        AppValueRow(
          label: 'Access Balance Remaining',
          value: NumberFormatService.formatAmount(
            state.remainingPrincipal,
            decimals: 2,
          ),
          valueColor: state.remainingPrincipal == 0
              ? Colors.green
              : colorScheme.error,
        ),

        Divider(height: spacing.lg),

        AppValueRow(
          label: 'New Balance',
          value: NumberFormatService.formatAmount(
            state.remainingBalance,
            decimals: 2,
          ),
          valueColor: state.remainingBalance == 0
              ? Colors.green
              : colorScheme.onSurface,
          addBottomSpacing: false,
        ),

        if (state.error != null) ...[
          SizedBox(height: spacing.md),
          Text(
            state.error!,
            style: AppTextStyles.small(
              context,
            ).copyWith(color: colorScheme.error),
          ),
        ],
      ],
    );
  }
}
