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
import 'package:ngoda/ui/functions/get_current_user.dart';
import 'package:ngoda/ui/functions/get_signed_transaction.dart';
import 'package:ngoda/ui/functions/get_wallet_balances.dart';
import 'package:ngoda/ui/functions/refresh_user_dashboard.dart';
import 'package:ngoda/ui/screens/wallet/transactions/provider/wallet_transaction_provider.dart';
import 'package:ngoda/ui/shared/app_text_styles.dart';
import 'package:ngoda/ui/widgets/app_button.dart';
import 'package:ngoda/ui/widgets/app_error_state.dart';
import 'package:ngoda/ui/widgets/app_value_row.dart';
import 'package:ngoda/ui/widgets/currency_field.dart';
import 'package:ngoda/ui/widgets/input_field.dart';
import 'package:ngoda/ui/widgets/payment_calculation_card.dart';
import 'package:ngoda/ui/widgets/view_header.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ReceiveCustomerDepositScreen extends ConsumerStatefulWidget {
  const ReceiveCustomerDepositScreen({super.key});

  @override
  ConsumerState<ReceiveCustomerDepositScreen> createState() =>
      _ReceiveCustomerDepositScreenState();
}

class _ReceiveCustomerDepositScreenState
    extends ConsumerState<ReceiveCustomerDepositScreen> {
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
    final iconSize = context.iconSize;
    final colorScheme = context.colorScheme;

    final state = ref.watch(walletTransactionProvider);

    final notifier = ref.read(walletTransactionProvider.notifier);

    final currencies = CurrencyService.all;

    if (currencies.isEmpty) {
      return Scaffold(
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: EdgeInsets.all(spacing.md),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.error_outline,
                    size: iconSize.large,
                    color: colorScheme.error,
                  ),

                  SizedBox(height: spacing.md),

                  Text(
                    'No currencies available',
                    textAlign: TextAlign.center,
                    style: AppTextStyles.medium(context),
                  ),

                  SizedBox(height: spacing.xs),

                  Text(
                    'Please log out and log in again',
                    textAlign: TextAlign.center,
                    style: AppTextStyles.small(context),
                  ),

                  SizedBox(height: spacing.lg),

                  AppButton(text: 'Go Back', onPressed: _closeScreen),
                ],
              ),
            ),
          ),
        ),
      );
    }

    final balances = getAgentWalletBalance(ref);

    if (balances == null) {
      return const Scaffold(
        body: SafeArea(
          child: AppErrorState(message: 'Failed to get agent wallet'),
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
                ViewHeader(
                  title: 'User Deposit',
                  subtitle: 'Receive customer deposit securely',
                  onClose: _closeScreen,
                ),

                Expanded(
                  child: SingleChildScrollView(
                    keyboardDismissBehavior:
                        ScrollViewKeyboardDismissBehavior.onDrag,
                    child: Column(
                      children: [
                        SizedBox(height: spacing.md),

                        Container(
                          width: double.infinity,
                          padding: EdgeInsets.all(spacing.md),
                          decoration: BoxDecoration(
                            color: context.theme.cardColor,
                            borderRadius: BorderRadius.circular(
                              radius.cardRadius,
                            ),
                            border: Border.all(
                              color: colorScheme.outlineVariant.withValues(
                                alpha: 0.09,
                              ),
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              CurrencyField(
                                selected: state.currency,
                                currencies: currencies,
                                balances: balances,
                                onSelect: (value) {
                                  notifier.updateCurrency(value, balances);

                                  if (amountCtrl.text.trim().isNotEmpty) {
                                    notifier.updateUserDepositAmount(
                                      amountCtrl.text,
                                    );
                                  }
                                },
                              ),

                              SizedBox(height: spacing.sm),

                              InputField(
                                controller: amountCtrl,
                                placeholder: 'Amount',
                                keyboardType:
                                    const TextInputType.numberWithOptions(
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

                              if (state.error != null &&
                                  state.error!.trim().isNotEmpty) ...[
                                SizedBox(height: spacing.sm),

                                Align(
                                  alignment: Alignment.centerLeft,
                                  child: Text(
                                    state.error!,
                                    style: AppTextStyles.tiny(
                                      context,
                                    ).copyWith(color: colorScheme.error),
                                  ),
                                ),
                              ],

                              if (state.currency != null &&
                                  state.amount > 0) ...[
                                SizedBox(height: spacing.lg),

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
                                      onPressed: _closeScreen,
                                    ),
                                  ),

                                  SizedBox(width: spacing.md),

                                  Expanded(
                                    child: AppButton(
                                      text: 'Deposit',
                                      isProcessing: state.isLoading,
                                      onPressed:
                                          !state.isValid || state.isLoading
                                          ? null
                                          : handleReceiveDeposit,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),

                        SizedBox(height: spacing.md),
                      ],
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

  Widget _buildCalculation() {
    final state = ref.watch(walletTransactionProvider);

    final currency = state.currency!.code;

    return PaymentCalculationCard(
      children: [
        AppValueRow(
          label: 'Amount',
          value: NumberFormatService.formatAmount(
            state.amount,
            currency: currency,
          ),
          addBottomSpacing: false,
        ),

        SizedBox(height: context.spacing.sm),

        AppValueRow(
          label: 'Fee',
          value: NumberFormatService.formatAmount(
            state.feeAmount,
            currency: currency,
          ),
          addBottomSpacing: false,
        ),

        Padding(
          padding: EdgeInsets.symmetric(vertical: context.spacing.sm),
          child: const Divider(),
        ),

        AppValueRow(
          label: 'Total Credit',
          value: NumberFormatService.formatAmount(
            state.amount,
            currency: currency,
          ),
          valueStyle: AppTextStyles.smallNumber(
            context,
          ).copyWith(fontWeight: FontWeight.w700),
          addBottomSpacing: false,
        ),
      ],
    );
  }

  Future<void> handleReceiveDeposit() async {
    try {
      final confirmed = await confirmDeposit();

      if (confirmed != true) {
        return;
      }

      final state = ref.read(walletTransactionProvider);

      final currentUser = getCurrentUser();

      final creditAgent = isCreditAgent(ref);

      _transactionListener.listenForTransactionStatus(
        reference: state.reference!,
        onTransactionSuccess: handleTransactionSuccess,
        onStatusChange: handleStatusChange,
      );

      final signedTransaction = await getSignedTransaction(
        v: 'v1',
        reference: state.reference!,
        identifier: currentUser.userId!,
        amount: state.amount,
        currency: state.currency!.code,
        taxAmount: creditAgent ? 1 : 0,
      );

      if (!mounted) {
        return;
      }

      final qrKey = GlobalKey();

      DialogService.transact(
        context,
        download: false,
        isDeposit: true,
        qrKey: qrKey,
        data: signedTransaction.transactionData,
        title: 'Scan to Deposit',
        onCancel: () {
          if (!mounted) {
            return;
          }

          _transactionListener.stop();

          _resetTransaction();

          if (context.canPop()) {
            context.pop();
          }
        },
      );
    } catch (error) {
      if (!mounted) {
        return;
      }

      await DialogService.error(context, message: error.toString());
    }
  }

  void handleStatusChange(String status) {
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
      if (!mounted) {
        return;
      }

      SnackbarService.error(
        context,
        'Change status error: ${error.toString()}',
      );
    }
  }

  Future<void> handleTransactionSuccess() async {
    try {
      if (!mounted) {
        return;
      }

      _transactionListener.stop();

      /*
       * Close the QR transaction dialog before
       * displaying the receipt.
       */
      if (context.canPop()) {
        context.pop();
      }

      if (!mounted) {
        return;
      }

      await showReceipt();

      if (!mounted) {
        return;
      }

      _resetTransaction();

      refreshUserDashboard(ref);
    } catch (error) {
      if (!mounted) {
        return;
      }

      await DialogService.error(context, message: error.toString());
    }
  }

  Future<bool?> confirmDeposit() {
    final state = ref.read(walletTransactionProvider);

    final currency = state.currency!.code;

    return DialogService.paymentConfirmation(
      context,
      title: 'Confirm User Deposit',
      rows: [
        PaymentRow(
          'Amount',
          NumberFormatService.formatAmount(state.amount, currency: currency),
        ),

        PaymentRow(
          'Fee',
          NumberFormatService.formatAmount(state.feeAmount, currency: currency),
        ),

        PaymentRow(
          'Total',
          NumberFormatService.formatAmount(state.amount, currency: currency),
          isBold: true,
        ),
      ],
    );
  }

  Future<void> showReceipt() async {
    final state = ref.read(walletTransactionProvider);

    final currency = state.currency!.code;

    final screenRoute = ModalRoute.of(context);

    await DialogService.paymentReceipt(
      context,
      title: 'Deposit Successful',
      rows: [
        PaymentRow(
          'Amount',
          NumberFormatService.formatAmount(state.amount, currency: currency),
          type: PaymentRowType.amount,
        ),

        PaymentRow(
          'Fee',
          NumberFormatService.formatAmount(state.feeAmount, currency: currency),
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

    await WidgetsBinding.instance.endOfFrame;

    while (mounted && screenRoute != null && !screenRoute.isCurrent) {
      await WidgetsBinding.instance.endOfFrame;
    }

    await Future<void>.delayed(const Duration(milliseconds: 200));
  }

  void _resetTransaction() {
    amountCtrl.clear();

    final notifier = ref.read(walletTransactionProvider.notifier);

    notifier.reset();
    notifier.initReference();
  }

  void _closeScreen() {
    if (!mounted) {
      return;
    }

    FocusScope.of(context).unfocus();

    _transactionListener.stop();

    _resetTransaction();

    if (context.canPop()) {
      context.pop();
    }
  }
}
