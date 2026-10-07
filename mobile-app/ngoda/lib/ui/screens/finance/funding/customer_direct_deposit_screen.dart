import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:ngoda/data_models/payment/payment_row.dart';
import 'package:ngoda/services/currency_service.dart';
import 'package:ngoda/services/dialog_service.dart';
import 'package:ngoda/services/number_format_service.dart';
import 'package:ngoda/ui/extensions/app_size.dart';
import 'package:ngoda/ui/extensions/theme_extension.dart';
import 'package:ngoda/ui/enums/enums.dart';
import 'package:ngoda/ui/functions/get_finance_balances.dart';
import 'package:ngoda/ui/screens/finance/providers/finance_dashboard_provider.dart';
import 'package:ngoda/ui/screens/finance/providers/finance_transaction_provider.dart';
import 'package:ngoda/ui/screens/finance/providers/transactions_config_provider.dart';
import 'package:ngoda/ui/shared/app_colors.dart';
import 'package:ngoda/ui/widgets/app_button.dart';
import 'package:ngoda/ui/widgets/app_error_state.dart';
import 'package:ngoda/ui/widgets/app_value_row.dart';
import 'package:ngoda/ui/widgets/currency_field.dart';
import 'package:ngoda/ui/widgets/input_field.dart';
import 'package:ngoda/ui/widgets/payment_calculation_card.dart';
import 'package:ngoda/ui/widgets/view_header.dart';

class CustomerDirectDepositScreen extends ConsumerStatefulWidget {
  const CustomerDirectDepositScreen({super.key});

  @override
  ConsumerState<CustomerDirectDepositScreen> createState() =>
      _CustomerDirectDepositScreenState();
}

class _CustomerDirectDepositScreenState
    extends ConsumerState<CustomerDirectDepositScreen> {
  final amountCtrl = TextEditingController();
  final emailCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();

    Future.microtask(() {
      ref.read(financeTransactionProvider.notifier).initReference();
    });
  }

  @override
  void dispose() {
    amountCtrl.dispose();
    emailCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    final radius = context.radius;
    final colorScheme = context.colorScheme;

    final state = ref.watch(financeTransactionProvider);

    final notifier = ref.read(financeTransactionProvider.notifier);

    final summary = ref.watch(financeDashboardProvider).value;

    final balances = getTreasuryBalances(summary?.result);

    final currencies = CurrencyService.all;

    if (currencies.isEmpty) {
      return Scaffold(
        body: SafeArea(
          child: AppErrorState(
            message: 'Failed to load currencies',
            onAction: () => context.pop(),
          ),
        ),
      );
    }

    return Scaffold(
      body: SafeArea(
        child: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTap: () {
            FocusScope.of(context).unfocus();
          },
          child: Column(
            children: [
              ViewHeader(
                title: 'Customer Direct Deposit',
                onClose: () {
                  _reset();
                  context.pop();
                },
              ),
              Expanded(
                child: SingleChildScrollView(
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  padding: EdgeInsets.all(spacing.padding),
                  child: Container(
                    width: double.infinity,
                    padding: EdgeInsets.all(spacing.padding),
                    decoration: BoxDecoration(
                      color: colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(radius.borderRadius),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        InputField(
                          controller: emailCtrl,
                          placeholder: 'Receiver email / phone',
                          keyboardType: TextInputType.emailAddress,
                          onChanged: notifier.updateEmail,
                        ),
                        SizedBox(height: spacing.sm),
                        CurrencyField(
                          selected: state.currency,
                          currencies: currencies,
                          onSelect: (value) {
                            notifier.updateCurrency(value, balances);
                          },
                          balances: balances,
                        ),
                        SizedBox(height: spacing.sm),
                        InputField(
                          controller: amountCtrl,
                          placeholder: 'Amount',
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          onChanged: (value) {
                            final transactionState = ref.read(
                              financeTransactionProvider,
                            );

                            final currency = transactionState.currency;

                            final config = ref
                                .read(transactionsConfigProvider)
                                .value;

                            if (config == null ||
                                currency == null ||
                                config.error != null) {
                              return;
                            }

                            final feeConfig = config.result?.get(
                              'customer_direct_deposit',
                              currency.code,
                            );

                            if (feeConfig == null) {
                              return;
                            }

                            notifier.updateDirectDepositAmount(
                              value,
                              balances[currency.code] ?? 0,
                              feeConfig: feeConfig,
                            );
                          },
                        ),
                        if (state.currency != null) ...[
                          SizedBox(height: spacing.sm),
                          _buildCalculation(context, state),
                        ],
                        SizedBox(height: spacing.lg),
                        Row(
                          children: [
                            Expanded(
                              child: AppButton(
                                text: 'Cancel',
                                isPrimary: false,
                                isDisabled: state.isLoading,
                                onPressed: () {
                                  _reset();
                                  context.pop();
                                },
                              ),
                            ),
                            SizedBox(width: spacing.sm),
                            Expanded(
                              child: AppButton(
                                text: 'User Deposit',
                                isProcessing: state.isLoading,
                                onPressed: !state.isValid || state.isLoading
                                    ? null
                                    : _handleUserDirectDeposit,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCalculation(BuildContext context, dynamic state) {
    final currency = state.currency?.code ?? 'usd';

    return PaymentCalculationCard(
      error: state.error,
      children: [
        AppValueRow(
          label: 'Available Balance',
          value: NumberFormatService.formatAmount(
            state.balance,
            currency: currency,
          ),
        ),
        AppValueRow(
          label: 'Fee (${state.feePercent.toStringAsFixed(2)}%)',
          value: NumberFormatService.formatAmount(
            state.feeAmount,
            currency: currency,
          ),
        ),
        AppValueRow(
          label: 'Net deposited',
          value: NumberFormatService.formatAmount(
            state.amount,
            currency: currency,
          ),
        ),
        AppValueRow(
          label: 'Total Debit',
          value: NumberFormatService.formatAmount(
            state.totalDebit,
            currency: currency,
          ),
          valueStyle: const TextStyle(fontWeight: FontWeight.w700),
        ),
        AppValueRow(
          label: 'New Balance',
          value: NumberFormatService.formatAmount(
            state.remaining,
            currency: currency,
          ),
          valueStyle: const TextStyle(fontWeight: FontWeight.w700),
          valueColor: state.remaining < 0 ? AppColors.error : AppColors.success,
          addBottomSpacing: false,
        ),
      ],
    );
  }

  Future<void> _handleUserDirectDeposit() async {
    try {
      final confirmed = await _confirmFunding();

      if (confirmed != true) {
        return;
      }

      if (!mounted) {
        return;
      }

      final notifier = ref.read(financeTransactionProvider.notifier);

      await notifier.customerDirectDeposit();

      ref.invalidate(financeDashboardProvider);

      if (!mounted) {
        return;
      }

      _showReceipt();

      emailCtrl.clear();
      amountCtrl.clear();
      notifier.reset();
    } catch (error) {
      if (!mounted) {
        return;
      }

      await DialogService.error(context, message: error.toString());
    }
  }

  Future<bool?> _confirmFunding() {
    final state = ref.read(financeTransactionProvider);

    return DialogService.paymentConfirmation(
      context,
      title: 'Confirm User Direct Deposit',
      rows: [
        PaymentRow('User', state.email, type: PaymentRowType.text),
        PaymentRow(
          'Amount',
          NumberFormatService.formatAmount(
            state.amount,
            currency: state.currency?.code ?? 'usd',
          ),
        ),
        PaymentRow(
          'Fee (${state.feePercent.toStringAsFixed(2)}%)',
          NumberFormatService.formatAmount(
            state.feeAmount,
            currency: state.currency?.code ?? 'usd',
          ),
        ),
        PaymentRow(
          'Total',
          NumberFormatService.formatAmount(
            state.totalDebit,
            currency: state.currency?.code ?? 'usd',
          ),
          isBold: true,
        ),
      ],
    );
  }

  void _showReceipt() {
    final state = ref.read(financeTransactionProvider);

    DialogService.paymentReceipt(
      context,
      title: 'User Direct Deposit Successful',
      rows: [
        PaymentRow('To', state.email, type: PaymentRowType.text),
        PaymentRow(
          'Amount',
          NumberFormatService.formatAmount(
            state.amount,
            currency: state.currency?.code ?? 'usd',
          ),
          type: PaymentRowType.amount,
        ),
        PaymentRow(
          'Fee (${state.feePercent.toStringAsFixed(2)}%)',
          NumberFormatService.formatAmount(
            state.feeAmount,
            currency: state.currency?.code ?? 'usd',
          ),
        ),
        PaymentRow(
          'Total',
          NumberFormatService.formatAmount(
            state.totalDebit,
            currency: state.currency?.code ?? 'usd',
          ),
          isBold: true,
        ),
      ],
      onDone: () {},
    );
  }

  void _reset() {
    amountCtrl.clear();
    emailCtrl.clear();

    ref.read(financeTransactionProvider.notifier).reset();
  }
}
