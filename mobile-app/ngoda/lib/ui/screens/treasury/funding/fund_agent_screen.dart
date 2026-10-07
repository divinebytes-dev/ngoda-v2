import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:ngoda/data_models/payment/payment_row.dart';
import 'package:ngoda/services/currency_service.dart';
import 'package:ngoda/services/dialog_service.dart';
import 'package:ngoda/services/number_format_service.dart';
import 'package:ngoda/ui/enums/enums.dart';
import 'package:ngoda/ui/extensions/app_size.dart';
import 'package:ngoda/ui/extensions/theme_extension.dart';
import 'package:ngoda/ui/functions/get_finance_balances.dart';
import 'package:ngoda/ui/screens/treasury/provider/treasury_dashboard_provider.dart';
import 'package:ngoda/ui/screens/treasury/provider/treasury_transaction_provider.dart';
import 'package:ngoda/ui/shared/app_text_styles.dart';
import 'package:ngoda/ui/widgets/app_button.dart';
import 'package:ngoda/ui/widgets/app_error_state.dart';
import 'package:ngoda/ui/widgets/app_value_row.dart';
import 'package:ngoda/ui/widgets/currency_field.dart';
import 'package:ngoda/ui/widgets/input_field.dart';
import 'package:ngoda/ui/widgets/payment_calculation_card.dart';
import 'package:ngoda/ui/widgets/view_header.dart';

class AgentFundingScreen extends ConsumerStatefulWidget {
  const AgentFundingScreen({super.key});

  @override
  ConsumerState<AgentFundingScreen> createState() => _AgentFundingScreenState();
}

class _AgentFundingScreenState extends ConsumerState<AgentFundingScreen> {
  final amountCtrl = TextEditingController();
  final emailCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }

      ref.read(treasuryTransactionProvider.notifier).initReference();
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
    final colorScheme = context.colorScheme;

    final state = ref.watch(treasuryTransactionProvider);
    final notifier = ref.read(treasuryTransactionProvider.notifier);

    final summary = ref.watch(treasuryDashboardProvider).value;

    final balances = getTreasuryWallet(summary?.result);

    final currencies = CurrencyService.all;

    if (currencies.isEmpty) {
      return Scaffold(
        body: AppErrorState(
          message: 'Failed to load currencies',
          onAction: () => context.pop(),
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
          child: ListView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: EdgeInsets.fromLTRB(
              spacing.md,
              spacing.md,
              spacing.md,
              spacing.lg,
            ),
            children: [
              /*
               * Header
               */

              ViewHeader(
                title: 'Agent Funding',
                subtitle: 'Transfer funds from treasury to an agent.',
                onClose: () => context.pop(),
              ),
              SizedBox(height: spacing.lg),

              /*
               * Funding details
               */
              // const _SectionLabel(
              //   title: 'Funding details',
              //   description: 'Enter the receiving agent and funding amount.',
              // ),

              // SizedBox(height: spacing.sm),
              Container(
                padding: EdgeInsets.all(spacing.md),
                decoration: BoxDecoration(
                  color: colorScheme.surface,
                  borderRadius: BorderRadius.circular(spacing.md),
                  border: Border.all(
                    color: colorScheme.outlineVariant.withValues(alpha: 0.5),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    InputField(
                      controller: emailCtrl,
                      placeholder: 'Receiver email',
                      keyboardType: TextInputType.emailAddress,
                      onChanged: notifier.updateEmail,
                    ),

                    SizedBox(height: spacing.sm),

                    CurrencyField(
                      selected: state.currency,
                      currencies: currencies,
                      balances: balances,
                      onSelect: (value) {
                        notifier.updateCurrency(value, balances);
                      },
                    ),

                    SizedBox(height: spacing.sm),

                    InputField(
                      controller: amountCtrl,
                      placeholder: 'Amount',
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      onChanged: (value) {
                        final currency = ref
                            .read(treasuryTransactionProvider)
                            .currency;

                        if (currency == null) {
                          return;
                        }

                        final balance = balances[currency.code];

                        notifier.updateAmount(value, balance ?? 0);
                      },
                    ),

                    if (state.currency != null) ...[
                      SizedBox(height: spacing.sm),
                      _buildCalculation(state),
                    ],
                  ],
                ),
              ),

              SizedBox(height: spacing.lg),

              /*
               * Actions
               */
              Row(
                children: [
                  Expanded(
                    child: AppButton(
                      text: 'Cancel',
                      isPrimary: false,
                      isDisabled: state.isLoading,
                      onPressed: _cancel,
                    ),
                  ),

                  SizedBox(width: spacing.sm),

                  Expanded(
                    child: AppButton(
                      text: 'Fund Agent',
                      isProcessing: state.isLoading,
                      onPressed: !state.isValid || state.isLoading
                          ? null
                          : _handleAgentFunding,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCalculation(dynamic state) {
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
          label: 'Total Debit',
          value: NumberFormatService.formatAmount(
            state.totalDebit,
            currency: currency,
          ),
        ),
        AppValueRow(
          label: 'New Balance',
          value: NumberFormatService.formatAmount(
            state.remaining,
            currency: currency,
          ),
          valueColor: state.remaining < 0
              ? context.colorScheme.error
              : Colors.green,
        ),
      ],
    );
  }

  void _cancel() {
    amountCtrl.clear();
    emailCtrl.clear();

    ref.read(treasuryTransactionProvider.notifier).reset();

    context.pop();
  }

  Future<void> _handleAgentFunding() async {
    try {
      final confirmed = await _confirmFunding();

      if (confirmed != true) {
        return;
      }

      if (!mounted) {
        return;
      }

      final notifier = ref.read(treasuryTransactionProvider.notifier);

      await notifier.fundAgent();

      ref.invalidate(treasuryDashboardProvider);

      if (!mounted) {
        return;
      }

      _showReceipt();

      emailCtrl.clear();
      amountCtrl.clear();

      notifier.reset();
      notifier.initReference();
    } catch (error) {
      if (!mounted) {
        return;
      }

      await DialogService.error(context, message: error.toString());
    }
  }

  Future<bool?> _confirmFunding() {
    final state = ref.read(treasuryTransactionProvider);

    return DialogService.paymentConfirmation(
      context,
      title: 'Confirm Agent Funding',
      rows: [
        PaymentRow('Agent', state.email, type: PaymentRowType.text),
        PaymentRow(
          'Amount',
          NumberFormatService.formatAmount(
            state.amount,
            currency: state.currency?.code ?? 'usd',
          ),
          isBold: true,
        ),
      ],
    );
  }

  void _showReceipt() {
    final state = ref.read(treasuryTransactionProvider);

    DialogService.paymentReceipt(
      context,
      title: 'Agent Funding Successful',
      rows: [
        PaymentRow('To', state.email, type: PaymentRowType.text),
        PaymentRow(
          'Amount',
          NumberFormatService.formatAmount(
            state.amount,
            currency: state.currency?.code ?? 'usd',
          ),
          type: PaymentRowType.amount,
          isBold: true,
        ),
      ],
      onDone: () {},
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.title, required this.description});

  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    final colorScheme = context.colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: AppTextStyles.small(
            context,
          ).copyWith(fontWeight: FontWeight.w700),
        ),
        SizedBox(height: spacing.xs),
        Text(
          description,
          style: AppTextStyles.tiny(
            context,
          ).copyWith(color: colorScheme.onSurfaceVariant),
        ),
      ],
    );
  }
}
