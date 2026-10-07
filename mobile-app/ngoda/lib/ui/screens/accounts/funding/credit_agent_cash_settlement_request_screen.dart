import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:ngoda/data_models/payment/payment_row.dart';
import 'package:ngoda/services/currency_service.dart';
import 'package:ngoda/services/dialog_service.dart';
import 'package:ngoda/services/number_format_service.dart';
import 'package:ngoda/services/snackbar_service.dart';
import 'package:ngoda/services/transaction_status_listener_service.dart';
import 'package:ngoda/ui/enums/enums.dart';
import 'package:ngoda/ui/extensions/app_size.dart';
import 'package:ngoda/ui/extensions/theme_extension.dart';
import 'package:ngoda/ui/functions/get_accounts_balances.dart';
import 'package:ngoda/ui/functions/get_current_user.dart';
import 'package:ngoda/ui/functions/get_signed_transaction.dart';
import 'package:ngoda/ui/screens/accounts/providers/accounts_dashboard_provider.dart';
import 'package:ngoda/ui/screens/wallet/transactions/provider/wallet_transaction_provider.dart';
import 'package:ngoda/ui/shared/app_text_styles.dart';
import 'package:ngoda/ui/widgets/app_button.dart';
import 'package:ngoda/ui/widgets/app_error_state.dart';
import 'package:ngoda/ui/widgets/app_value_row.dart';
import 'package:ngoda/ui/widgets/currency_field.dart';
import 'package:ngoda/ui/widgets/input_field.dart';
import 'package:ngoda/ui/widgets/payment_calculation_card.dart';
import 'package:ngoda/ui/widgets/screen_header.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class CreditAgentCashSettlementRequestScreen extends ConsumerStatefulWidget {
  const CreditAgentCashSettlementRequestScreen({super.key});

  @override
  ConsumerState<CreditAgentCashSettlementRequestScreen> createState() =>
      _CreditAgentCashSettlementRequestScreenState();
}

class _CreditAgentCashSettlementRequestScreenState
    extends ConsumerState<CreditAgentCashSettlementRequestScreen> {
  final amountCtrl = TextEditingController();

  late final TransactionStatusListenerService _transactionListener;

  @override
  void initState() {
    super.initState();

    _transactionListener = TransactionStatusListenerService(
      supabase: Supabase.instance.client,
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }

      ref.read(walletTransactionProvider.notifier).initReference();
    });
  }

  @override
  void dispose() {
    _transactionListener.stop();
    amountCtrl.dispose();

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    final radius = context.radius;
    final colorScheme = context.colorScheme;

    final state = ref.watch(walletTransactionProvider);

    final notifier = ref.read(walletTransactionProvider.notifier);

    final dashboardAsync = ref.watch(accountsDashboardProvider);

    final dashboard = dashboardAsync.value;

    final currencies = CurrencyService.all;

    if (currencies.isEmpty) {
      return Scaffold(
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: EdgeInsets.all(spacing.lg),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.error_outline,
                    size: context.iconSize.small,
                    color: colorScheme.error,
                  ),
                  SizedBox(height: spacing.sm),
                  Text(
                    'No currencies available',
                    style: AppTextStyles.medium(context),
                    textAlign: TextAlign.center,
                  ),
                  SizedBox(height: spacing.xs),
                  Text(
                    'Please try logout and login again',
                    style: AppTextStyles.small(
                      context,
                    ).copyWith(color: colorScheme.onSurfaceVariant),
                    textAlign: TextAlign.center,
                  ),
                  SizedBox(height: spacing.lg),
                  AppButton(
                    text: 'Go Back',
                    onPressed: () {
                      Navigator.of(context).maybePop();
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    final balances = getAccountsBalances(dashboard?.result);

    if (balances.isEmpty) {
      return Scaffold(
        body: SafeArea(
          child: AppErrorState(
            message: 'Failed to get agent wallet',
            onAction: () {
              Navigator.of(context).maybePop();
            },
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
                  title: 'Credit Agent Cash Settlement',
                  subtitle: 'Cash settlement request',
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
                                  .read(walletTransactionProvider)
                                  .currency;

                              if (currency == null) {
                                return;
                              }

                              notifier.updateUserDepositAmount(value);
                            },
                          ),
                          if (state.currency != null && state.amount > 0) ...[
                            SizedBox(height: spacing.md),
                            _buildCalculation(),
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

                                          notifier.initReference();

                                          context.pop();
                                        },
                                ),
                              ),
                              SizedBox(width: spacing.sm),
                              Expanded(
                                child: AppButton(
                                  text: 'Settle',
                                  isProcessing: state.isLoading,
                                  onPressed: !state.isValid || state.isLoading
                                      ? null
                                      : () async {
                                          await _handleReceiveSettlement();
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

  Future<void> _handleReceiveSettlement() async {
    try {
      final qrKey = GlobalKey();

      final confirmed = await _confirmSettlement();

      if (confirmed != true) {
        return;
      }

      final state = ref.read(walletTransactionProvider);

      final user = getCurrentUser();

      _transactionListener.listenForTransactionStatus(
        reference: state.reference!,
        onTransactionSuccess: _handleTransactionSuccess,
        onStatusChange: _handleStatusChange,
      );

      final signedTransaction = await getSignedTransaction(
        v: 'v8',
        reference: state.reference!,
        identifier: user.userId!,
        amount: state.amount,
        currency: state.currency!.code,
        taxAmount: 0,
      );

      if (!mounted) {
        return;
      }

      DialogService.transact(
        context,
        download: false,
        isDeposit: true,
        qrKey: qrKey,
        data: signedTransaction.transactionData,
        title: 'Scan to Settle',
        onCancel: () {
          if (!context.mounted) {
            return;
          }

          amountCtrl.clear();

          final notifier = ref.read(walletTransactionProvider.notifier);

          notifier.reset();
          notifier.initReference();

          context.pop();
        },
      );
    } catch (e) {
      if (!mounted) {
        return;
      }

      await DialogService.error(context, message: e.toString());
    }
  }

  void _handleStatusChange(String status) {
    if (!mounted) {
      return;
    }

    try {
      final notifier = ref.read(walletTransactionProvider.notifier);

      switch (status) {
        case 'processing':
          notifier.setTransactionStatus(TransactionStatus.processing);
          break;

        case 'failed':
          notifier.setTransactionStatus(TransactionStatus.failed);
          break;

        case 'success':
          notifier.setTransactionStatus(TransactionStatus.success);
          break;
      }
    } catch (error) {
      if (!context.mounted) {
        return;
      }

      SnackbarService.error(
        context,
        'Change status error: ${error.toString()}',
      );
    }
  }

  Future<void> _handleTransactionSuccess() async {
    try {
      if (!mounted) {
        return;
      }

      context.pop();

      await _showReceipt();

      amountCtrl.clear();

      final notifier = ref.read(walletTransactionProvider.notifier);

      notifier.reset();
      notifier.initReference();
    } catch (e) {
      if (!mounted) {
        return;
      }

      await DialogService.error(context, message: e.toString());
    }
  }

  Widget _buildCalculation() {
    final state = ref.read(walletTransactionProvider);

    final currency = state.currency!.code;

    return PaymentCalculationCard(
      error: state.error,
      children: [
        AppValueRow(
          label: 'Amount',
          value: NumberFormatService.formatAmount(
            state.amount,
            currency: currency,
          ),
        ),
        AppValueRow(
          label: 'Total Credit',
          value: NumberFormatService.formatAmount(
            state.amount,
            currency: currency,
          ),
          addBottomSpacing: false,
        ),
      ],
    );
  }

  Future<bool?> _confirmSettlement() {
    final state = ref.read(walletTransactionProvider);

    final currency = state.currency!.code;

    return DialogService.paymentConfirmation(
      context,
      title: 'Confirm Credit Agent Cash Settlement',
      rows: [
        PaymentRow(
          'Amount',
          NumberFormatService.formatAmount(state.amount, currency: currency),
        ),
        PaymentRow(
          'Total',
          NumberFormatService.formatAmount(state.amount, currency: currency),
          isBold: true,
        ),
      ],
    );
  }

  Future<void> _showReceipt() async {
    final state = ref.read(walletTransactionProvider);

    final currency = state.currency!.code;

    await DialogService.paymentReceipt(
      context,
      title: 'Credit Agent Cash Settlement Successful',
      rows: [
        PaymentRow(
          'Amount',
          NumberFormatService.formatAmount(state.amount, currency: currency),
          type: PaymentRowType.amount,
        ),
        PaymentRow(
          'Total',
          NumberFormatService.formatAmount(state.amount, currency: currency),
          type: PaymentRowType.amount,
          isBold: true,
        ),
      ],
      onDone: () {},
    );
  }
}
