import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:ngoda/data_models/payment/payment_row.dart';
import 'package:ngoda/services/currency_service.dart';
import 'package:ngoda/services/dialog_service.dart';
import 'package:ngoda/services/number_format_service.dart';
import 'package:ngoda/ui/extensions/app_size.dart';
import 'package:ngoda/ui/extensions/theme_extension.dart';
import 'package:ngoda/ui/functions/refresh_user_dashboard.dart';
import 'package:ngoda/ui/screens/accounts/providers/accounts_dashboard_provider.dart';
import 'package:ngoda/ui/screens/accounts/providers/accounts_transaction_provider.dart';
import 'package:ngoda/ui/screens/finance/providers/recent_transactions_provider.dart';
import 'package:ngoda/ui/widgets/app_button.dart';
import 'package:ngoda/ui/widgets/app_error_state.dart';
import 'package:ngoda/ui/widgets/app_value_row.dart';
import 'package:ngoda/ui/widgets/currency_field.dart';
import 'package:ngoda/ui/widgets/input_field.dart';
import 'package:ngoda/ui/widgets/payment_calculation_card.dart';
import 'package:ngoda/ui/widgets/screen_header.dart';

class TreasuryFundingScreen extends ConsumerStatefulWidget {
  const TreasuryFundingScreen({super.key});

  @override
  ConsumerState<TreasuryFundingScreen> createState() =>
      _TreasuryFundingScreenState();
}

class _TreasuryFundingScreenState extends ConsumerState<TreasuryFundingScreen> {
  final amountCtrl = TextEditingController();

  @override
  void dispose() {
    amountCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    final radius = context.radius;
    final colorScheme = context.colorScheme;

    final state = ref.watch(accountsTransactionProvider);

    final notifier = ref.read(accountsTransactionProvider.notifier);

    final summary = ref.watch(accountsDashboardProvider).value;

    final bankNet = summary?.result?.bankNet;
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

    if (bankNet == null) {
      return Scaffold(
        body: SafeArea(
          child: AppErrorState(
            message: 'Failed to load treasury balances',
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
          child: Padding(
            padding: EdgeInsets.all(spacing.md),
            child: Column(
              children: [
                const ScreenHeader(
                  title: 'Treasury Funding',
                  subtitle: 'Fund treasury',
                ),
                SizedBox(height: spacing.md),
                Expanded(
                  child: SingleChildScrollView(
                    keyboardDismissBehavior:
                        ScrollViewKeyboardDismissBehavior.onDrag,
                    child: Container(
                      width: double.infinity,
                      padding: EdgeInsets.all(spacing.md),
                      decoration: BoxDecoration(
                        color: colorScheme.surface,
                        borderRadius: BorderRadius.circular(
                          radius.borderRadius,
                        ),
                        border: Border.all(color: colorScheme.outlineVariant),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          CurrencyField(
                            selected: state.currency,
                            currencies: currencies,
                            onSelect: (value) {
                              notifier.updateCurrency(value, bankNet);
                            },
                            balances: bankNet,
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
                                  .read(accountsTransactionProvider)
                                  .currency;

                              if (currency == null) {
                                return;
                              }

                              final balance = bankNet[currency.code];

                              notifier.updateAmountTreasury(
                                value,
                                balance ?? 0,
                              );
                            },
                          ),
                          if (state.currency != null) ...[
                            SizedBox(height: spacing.md),
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
                                  onPressed: state.isLoading
                                      ? null
                                      : () {
                                          amountCtrl.clear();

                                          notifier.reset();

                                          context.pop();
                                        },
                                ),
                              ),
                              SizedBox(width: spacing.sm),
                              Expanded(
                                child: AppButton(
                                  text: 'Fund Treasury',
                                  isProcessing: state.isLoading,
                                  onPressed: !state.isValid || state.isLoading
                                      ? null
                                      : () async {
                                          await _handleTreasuryFunding(
                                            state.amount,
                                            state.currency!.code,
                                          );
                                        },
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
      ),
    );
  }

  Widget _buildCalculation(BuildContext context, dynamic state) {
    final currency = state.currency?.code ?? 'usd';
    final colorScheme = context.colorScheme;

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
              ? colorScheme.error
              : colorScheme.primary,
          addBottomSpacing: false,
        ),
      ],
    );
  }

  Future<void> _handleTreasuryFunding(double amount, String currency) async {
    try {
      final confirmed = await _confirmFunding();

      if (confirmed != true) {
        return;
      }

      if (!mounted) {
        return;
      }

      final notifier = ref.read(accountsTransactionProvider.notifier);

      await notifier.fundTreasury(currency: currency, amount: amount);

      ref.invalidate(accountsTransactionProvider);

      ref.invalidate(recentTransactionsProvider);

      if (!mounted) {
        return;
      }

      await DialogService.success(
        context,
        message: 'Treasury Funded Successfully',
      );

      amountCtrl.clear();

      refreshUserDashboard(ref);

      ref.read(accountsTransactionProvider.notifier).reset();
    } catch (e) {
      if (!mounted) {
        return;
      }

      await DialogService.error(context, message: e.toString());
    }
  }

  Future<bool?> _confirmFunding() {
    final state = ref.read(accountsTransactionProvider);

    return DialogService.paymentConfirmation(
      context,
      title: 'Confirm Treasury Funding',
      rows: [
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
}
