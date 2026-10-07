import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:ngoda/data_models/payment/payment_row.dart';
import 'package:ngoda/services/currency_service.dart';
import 'package:ngoda/services/dialog_service.dart';
import 'package:ngoda/services/number_format_service.dart';
import 'package:ngoda/ui/extensions/app_size.dart';
import 'package:ngoda/ui/extensions/theme_extension.dart';
import 'package:ngoda/ui/functions/get_finance_balances.dart';
import 'package:ngoda/ui/screens/finance/providers/finance_dashboard_provider.dart';
import 'package:ngoda/ui/screens/finance/providers/finance_transaction_provider.dart';
import 'package:ngoda/ui/widgets/app_button.dart';
import 'package:ngoda/ui/widgets/app_error_state.dart';
import 'package:ngoda/ui/widgets/currency_field.dart';
import 'package:ngoda/ui/widgets/input_field.dart';
import 'package:ngoda/ui/widgets/view_header.dart';

class ExternalFundingScreen extends ConsumerStatefulWidget {
  const ExternalFundingScreen({super.key});

  @override
  ConsumerState<ExternalFundingScreen> createState() =>
      _ExternalFundingScreenState();
}

class _ExternalFundingScreenState extends ConsumerState<ExternalFundingScreen> {
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

    final state = ref.watch(financeTransactionProvider);

    final notifier = ref.read(financeTransactionProvider.notifier);

    final summary = ref.watch(financeDashboardProvider).value;

    final balances = getFinanceBalances(summary?.result);

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
                title: 'External Funding',
                onClose: () {
                  amountCtrl.clear();
                  notifier.reset();
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
                            final currency = ref
                                .read(financeTransactionProvider)
                                .currency;

                            if (currency == null) {
                              return;
                            }

                            notifier.updateAmountExt(value);
                          },
                        ),
                        SizedBox(height: spacing.lg),
                        Row(
                          children: [
                            Expanded(
                              child: AppButton(
                                text: 'Cancel',
                                isPrimary: false,
                                isDisabled: state.isLoading,
                                onPressed: () {
                                  amountCtrl.clear();
                                  notifier.reset();
                                  context.pop();
                                },
                              ),
                            ),
                            SizedBox(width: spacing.sm),
                            Expanded(
                              child: AppButton(
                                text: 'Fund',
                                isProcessing: state.isLoading,
                                onPressed: !state.isValid || state.isLoading
                                    ? null
                                    : () async {
                                        await _handleExternalFund(
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
    );
  }

  Future<void> _handleExternalFund(double amount, String currency) async {
    try {
      final confirmed = await _confirmFunding();

      if (confirmed != true) {
        return;
      }

      if (!mounted) {
        return;
      }

      final notifier = ref.read(financeTransactionProvider.notifier);

      await notifier.externalFunding(currency: currency, amount: amount);

      ref.invalidate(financeDashboardProvider);

      if (!mounted) {
        return;
      }

      await DialogService.success(
        context,
        message: 'External funding successful',
      );

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
      title: 'Confirm External Funding',
      rows: [
        PaymentRow(
          'Amount',
          NumberFormatService.formatAmount(
            state.amount,
            currency: state.currency!.code,
          ),
          isBold: true,
        ),
      ],
    );
  }
}
