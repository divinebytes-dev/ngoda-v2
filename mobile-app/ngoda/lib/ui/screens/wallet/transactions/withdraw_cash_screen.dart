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
import 'package:ngoda/ui/functions/refresh_user_dashboard.dart';
import 'package:ngoda/ui/screens/finance/providers/transactions_config_provider.dart';
import 'package:ngoda/ui/screens/wallet/transactions/provider/customer_transaction_setup_provider.dart';
import 'package:ngoda/ui/screens/wallet/transactions/provider/wallet_transaction_provider.dart';
import 'package:ngoda/ui/shared/app_text_styles.dart';
import 'package:ngoda/ui/widgets/app_button.dart';
import 'package:ngoda/ui/widgets/app_value_row.dart';
import 'package:ngoda/ui/widgets/currency_field.dart';
import 'package:ngoda/ui/widgets/input_field.dart';
import 'package:ngoda/ui/widgets/payment_calculation_card.dart';
import 'package:ngoda/ui/widgets/view_header.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class WithdrawCashScreen extends ConsumerStatefulWidget {
  const WithdrawCashScreen({super.key});

  @override
  ConsumerState<WithdrawCashScreen> createState() => _WithdrawCashScreenState();
}

class _WithdrawCashScreenState extends ConsumerState<WithdrawCashScreen> {
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

    final setupAsync = ref.watch(customerTransactionSetupProvider);

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

    if (setupAsync.isLoading) {
      return Scaffold(
        body: SafeArea(
          child: Center(
            child: CircularProgressIndicator(color: colorScheme.primary),
          ),
        ),
      );
    }

    if (setupAsync.hasError || setupAsync.value == null) {
      return Scaffold(
        body: SafeArea(
          child: Padding(
            padding: EdgeInsets.all(spacing.md),
            child: Center(
              child: Text(
                setupAsync.hasError
                    ? setupAsync.error.toString()
                    : 'Failed to load wallet balances',
                textAlign: TextAlign.center,
                style: AppTextStyles.small(
                  context,
                ).copyWith(color: colorScheme.error),
              ),
            ),
          ),
        ),
      );
    }

    final setup = setupAsync.value!;
    final balances = setup.balances;

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
                  title: 'Withdraw Money',
                  subtitle: 'Withdraw funds securely',
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
                            // boxShadow: [
                            //   BoxShadow(
                            //     color: colorScheme.shadow.withValues(
                            //       alpha: 0.05,
                            //     ),
                            //     blurRadius: spacing.lg,
                            //     offset: Offset(0, spacing.sm),
                            //   ),
                            // ],
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
                                    _updateWithdrawalAmount(amountCtrl.text);
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
                                onChanged: _updateWithdrawalAmount,
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
                                      text: 'Withdraw',
                                      isProcessing: state.isLoading,
                                      onPressed:
                                          !state.isValid || state.isLoading
                                          ? null
                                          : handleCashWithdrawal,
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

  void _updateWithdrawalAmount(String value) {
    final config = ref.read(transactionsConfigProvider).value;

    final state = ref.read(walletTransactionProvider);

    final currency = state.currency;

    final setup = ref.read(customerTransactionSetupProvider).value;

    if (config == null || currency == null || setup == null) {
      return;
    }

    if (config.error != null) {
      return;
    }

    final code = currency.code;

    final feeConfig = config.result?.get('cash_withdrawal', code);

    final taxConfig = config.result?.get('cash_withdrawal_tax', code);

    if (feeConfig == null || taxConfig == null) {
      return;
    }

    final balance = setup.balances[code] ?? 0;

    ref
        .read(walletTransactionProvider.notifier)
        .updateWithdrawAmount(
          value,
          feeConfig: feeConfig,
          taxConfig: taxConfig,
          balance: balance,
        );
  }

  Widget _buildCalculation() {
    final state = ref.watch(walletTransactionProvider);

    final currency = state.currency!.code;

    final remainingStyle = AppTextStyles.smallNumber(context).copyWith(
      fontWeight: FontWeight.w700,
      color: state.remaining < 0
          ? context.colorScheme.error
          : context.colorScheme.primary,
    );

    return PaymentCalculationCard(
      children: [
        AppValueRow(
          label: 'Available Balance',
          value: NumberFormatService.formatAmount(
            state.balance,
            currency: currency,
          ),
          labelStyle: AppTextStyles.small(
            context,
          ).copyWith(color: context.colorScheme.onSurfaceVariant),
          valueStyle: AppTextStyles.smallNumber(
            context,
          ).copyWith(color: context.colorScheme.onSurfaceVariant),
          addBottomSpacing: false,
        ),

        SizedBox(height: context.spacing.sm),

        AppValueRow(
          label: 'Fee (${state.feePercent.toStringAsFixed(2)}%)',
          value: NumberFormatService.formatAmount(
            state.feeAmount,
            currency: currency,
          ),
          addBottomSpacing: false,
        ),

        SizedBox(height: context.spacing.sm),

        AppValueRow(
          label: 'Tax (${state.taxPercent.toStringAsFixed(2)}%)',
          value: NumberFormatService.formatAmount(
            state.taxAmount,
            currency: currency,
          ),
          addBottomSpacing: false,
        ),

        Padding(
          padding: EdgeInsets.symmetric(vertical: context.spacing.sm),
          child: const Divider(),
        ),

        AppValueRow(
          label: 'Total Debit',
          value: NumberFormatService.formatAmount(
            state.totalDebit,
            currency: currency,
          ),
          valueStyle: AppTextStyles.smallNumber(
            context,
          ).copyWith(fontWeight: FontWeight.w700),
          addBottomSpacing: false,
        ),

        SizedBox(height: context.spacing.sm),

        AppValueRow(
          label: 'New Balance',
          value: NumberFormatService.formatAmount(
            state.remaining,
            currency: currency,
          ),
          valueStyle: remainingStyle,
          addBottomSpacing: false,
        ),
      ],
    );
  }

  Future<void> handleCashWithdrawal() async {
    try {
      final confirmed = await confirmWithdrawal();

      if (confirmed != true) {
        return;
      }

      final state = ref.read(walletTransactionProvider);

      final user = getCurrentUser();

      _transactionListener.listenForTransactionStatus(
        reference: state.reference!,
        onTransactionSuccess: handleTransactionSuccess,
        onStatusChange: handleStatusChange,
      );

      final signedTransaction = await getSignedTransaction(
        v: 'v3',
        reference: state.reference!,
        identifier: user.userId!,
        amount: state.amount,
        feeAmount: state.feeAmount,
        taxAmount: state.taxAmount,
        currency: state.currency!.code,
      );

      if (!mounted) {
        return;
      }

      final qrKey = GlobalKey();

      DialogService.transact(
        context,
        download: false,
        qrKey: qrKey,
        data: signedTransaction.transactionData,
        title: 'Scan to Withdraw',
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

      _transactionListener.stop();

      await DialogService.error(context, message: error.toString());

      if (!mounted) {
        return;
      }

      _resetTransaction();
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
       * Close the QR transaction dialog.
       */
      if (context.canPop()) {
        context.pop();
      }

      if (!mounted) {
        return;
      }

      refreshUserDashboard(ref);

      await showReceipt();

      if (!mounted) {
        return;
      }

      _resetTransaction();
    } catch (error) {
      if (!mounted) {
        return;
      }

      await DialogService.error(context, message: error.toString());
    }
  }

  Future<bool?> confirmWithdrawal() {
    final state = ref.read(walletTransactionProvider);

    final currency = state.currency!.code;

    return DialogService.paymentConfirmation(
      context,
      title: 'Confirm Withdrawal',
      rows: [
        PaymentRow(
          'Amount',
          NumberFormatService.formatAmount(state.amount, currency: currency),
        ),

        PaymentRow(
          'Fee (${state.feePercent.toStringAsFixed(2)}%)',
          NumberFormatService.formatAmount(state.feeAmount, currency: currency),
        ),

        PaymentRow(
          'Tax (${state.taxPercent.toStringAsFixed(2)}%)',
          NumberFormatService.formatAmount(state.taxAmount, currency: currency),
        ),

        PaymentRow(
          'Total',
          NumberFormatService.formatAmount(
            state.totalDebit,
            currency: currency,
          ),
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
      title: 'Withdrawal Successful',
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
          'Tax',
          NumberFormatService.formatAmount(state.taxAmount, currency: currency),
          type: PaymentRowType.amount,
        ),

        PaymentRow(
          'Total',
          NumberFormatService.formatAmount(
            state.totalDebit,
            currency: currency,
          ),
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
