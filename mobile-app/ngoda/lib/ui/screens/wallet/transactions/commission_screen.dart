import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:ngoda/data_models/payment/payment_row.dart';
import 'package:ngoda/data_models/wallet/wallet_balance_summary.dart';
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
import 'package:ngoda/ui/screens/wallet/reports/provider/multi_wallet_summary_provider.dart';
import 'package:ngoda/ui/screens/wallet/transactions/provider/wallet_transaction_provider.dart';
import 'package:ngoda/ui/shared/app_text_styles.dart';
import 'package:ngoda/ui/widgets/app_button.dart';
import 'package:ngoda/ui/widgets/app_value_row.dart';
import 'package:ngoda/ui/widgets/currency_field.dart';
import 'package:ngoda/ui/widgets/input_field.dart';
import 'package:ngoda/ui/widgets/payment_calculation_card.dart';
import 'package:ngoda/ui/widgets/view_header.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class CommissionScreen extends ConsumerStatefulWidget {
  const CommissionScreen({super.key});

  @override
  ConsumerState<CommissionScreen> createState() => _CommissionScreenState();
}

class _CommissionScreenState extends ConsumerState<CommissionScreen> {
  final amountCtrl = TextEditingController();
  bool _isSubmitting = false;
  bool _withdrawSelected = true;

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

      _resetTransaction();
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

    final setupAsync = ref.watch(multiWalletSummaryProvider);
    final config = ref.watch(transactionsConfigProvider);

    final state = ref.watch(walletTransactionProvider);

    final notifier = ref.read(walletTransactionProvider.notifier);

    final wallet = setupAsync.value?.result?.commissionWallet;
    final balances = <String, double>{
      for (final code in wallet?.sortedCurrencyList ?? const <String>[])
        if (code.toLowerCase() != 'gold')
          code: wallet?.walletBalances.getByCurrency(code)?.balance ?? 0.0,
    };
    final currencies = CurrencyService.all
        .where((currency) => balances.containsKey(currency.code))
        .toList();
    final role = getCurrentUser().role;
    final canTransfer = role == 'agent' || role == 'vendor';
    final canWithdraw = canTransfer || role == 'merchant';
    final submitting = _isSubmitting || state.isLoading;
    final currencyCode = state.currency?.code;
    final balance = balances[currencyCode];
    final fees = config.value?.result;
    final amountText = amountCtrl.text.trim();
    final canQuote =
        balance != null &&
        currencyCode != null &&
        fees != null &&
        !config.isLoading &&
        !config.hasError &&
        config.value?.error == null;
    final withdraw = !canTransfer || _withdrawSelected;
    final actionLabel = withdraw ? 'Withdraw' : 'Transfer';
    final quote = canQuote && canWithdraw
        ? notifier.calculateCommissionQuote(
            amountText,
            balance: balance,
            feeConfig: fees.get(
              withdraw ? 'commission_withdrawal' : 'commission_transfer',
              currencyCode,
            ),
            taxConfig: withdraw
                ? fees.get('commission_withdrawal_tax', currencyCode)
                : null,
          )
        : null;
    final canSubmit = !submitting && state.reference != null;

    if (!setupAsync.isLoading &&
        !setupAsync.hasError &&
        setupAsync.value?.result != null &&
        setupAsync.value?.error == null &&
        currencies.isEmpty) {
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

    if (setupAsync.hasError ||
        setupAsync.value?.result == null ||
        setupAsync.value?.error != null) {
      return Scaffold(
        body: SafeArea(
          child: Padding(
            padding: EdgeInsets.all(spacing.md),
            child: Center(
              child: Text(
                setupAsync.hasError
                    ? setupAsync.error.toString()
                    : setupAsync.value?.error?.toString() ??
                          'Failed to load commission balances',
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
                  title: 'Process Commission',
                  subtitle: 'Withdraw or transfer your commission',
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
                              if (canTransfer) ...[
                                Wrap(
                                  spacing: spacing.sm,
                                  children: [
                                    ChoiceChip(
                                      label: const Text('Withdraw'),
                                      selected: withdraw,
                                      onSelected: submitting
                                          ? null
                                          : (_) => setState(
                                              () => _withdrawSelected = true,
                                            ),
                                    ),
                                    ChoiceChip(
                                      label: const Text('Transfer'),
                                      selected: !withdraw,
                                      onSelected: submitting
                                          ? null
                                          : (_) => setState(
                                              () => _withdrawSelected = false,
                                            ),
                                    ),
                                  ],
                                ),
                                SizedBox(height: spacing.sm),
                              ],
                              CurrencyField(
                                selected: state.currency,
                                currencies: currencies,
                                balances: balances,
                                onSelect: (value) {
                                  if (!submitting) {
                                    notifier.updateCurrency(value, balances);
                                  }
                                },
                              ),

                              SizedBox(height: spacing.sm),

                              InputField(
                                controller: amountCtrl,
                                enabled: !submitting,
                                placeholder: 'Amount',
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                      decimal: true,
                                    ),
                                onChanged: (_) => setState(() {}),
                              ),

                              if (amountText.isNotEmpty &&
                                  currencyCode != null) ...[
                                SizedBox(height: spacing.md),
                                if (quote != null && quote.amount > 0)
                                  _buildCalculation(
                                    title: withdraw ? 'Withdrawal' : 'Transfer',
                                    currency: currencyCode,
                                    amount: quote.amount,
                                    fee: quote.fee,
                                    tax: quote.tax,
                                    remaining: quote.remaining,
                                    insufficient: quote.insufficient,
                                  ),
                                if (!canQuote)
                                  Text(
                                    config.isLoading
                                        ? 'Loading commission fees…'
                                        : 'Commission fees are unavailable.',
                                    style: AppTextStyles.small(context),
                                  )
                                else if (quote?.amount == 0)
                                  Text(
                                    'Enter an amount with up to two decimal places.',
                                    style: AppTextStyles.small(context),
                                  ),
                              ],

                              SizedBox(height: spacing.lg),

                              SizedBox(
                                width: double.infinity,
                                child: AppButton(
                                  text: actionLabel,
                                  isProcessing: submitting,
                                  onPressed:
                                      canSubmit && (quote?.isValid ?? false)
                                      ? () => _submit(withdraw: withdraw)
                                      : null,
                                ),
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

  Widget _buildCalculation({
    required String title,
    required String currency,
    required double amount,
    required double fee,
    required double tax,
    required double remaining,
    required bool insufficient,
  }) {
    return PaymentCalculationCard(
      children: [
        Text(title, style: AppTextStyles.small(context)),
        SizedBox(height: context.spacing.sm),
        AppValueRow(
          label: 'Amount',
          value: NumberFormatService.formatAmount(amount, currency: currency),
        ),
        AppValueRow(
          label: 'Fee',
          value: NumberFormatService.formatAmount(fee, currency: currency),
        ),
        if (tax > 0)
          AppValueRow(
            label: 'Tax',
            value: NumberFormatService.formatAmount(tax, currency: currency),
          ),
        AppValueRow(
          label: 'Remaining Balance',
          value: NumberFormatService.formatAmount(
            remaining,
            currency: currency,
          ),
          valueStyle: AppTextStyles.smallNumber(
            context,
          ).copyWith(color: insufficient ? context.colorScheme.error : null),
          addBottomSpacing: false,
        ),
      ],
    );
  }

  Future<void> _submit({required bool withdraw}) async {
    if (_isSubmitting) {
      return;
    }

    final current = ref.read(walletTransactionProvider);
    final currency = current.currency?.code;
    if (current.isLoading || currency == null || current.reference == null) {
      return;
    }

    final balances = ref.read(multiWalletSummaryProvider).value;
    final balance = balances?.result?.commissionWallet.walletBalances
        .getByCurrency(currency)
        ?.balance;
    if (balances?.error != null || balance == null) {
      SnackbarService.error(context, 'Failed to load commission balance.');
      return;
    }

    final config = ref.read(transactionsConfigProvider);
    final fees = config.value?.result;
    if (config.isLoading ||
        config.hasError ||
        config.value?.error != null ||
        fees == null) {
      SnackbarService.error(context, 'Commission fees are unavailable.');
      return;
    }

    final notifier = ref.read(walletTransactionProvider.notifier);
    if (withdraw) {
      notifier.updateWithdrawalCommission(
        amountCtrl.text,
        balance: balance,
        feeConfig: fees.get('commission_withdrawal', currency),
        taxConfig: fees.get('commission_withdrawal_tax', currency),
      );
    } else {
      notifier.updateTransferCommission(
        amountCtrl.text,
        balance: balance,
        feeConfig: fees.get('commission_transfer', currency),
      );
    }

    final quote = ref.read(walletTransactionProvider);
    if (!quote.isValid) {
      SnackbarService.error(
        context,
        quote.error ?? 'Enter a valid commission amount.',
      );
      return;
    }

    setState(() => _isSubmitting = true);
    try {
      final confirmed = await _confirmTransaction(withdraw: withdraw);
      if (!mounted || confirmed != true) {
        return;
      }

      if (withdraw) {
        await _showWithdrawalQr();
      } else {
        await notifier.transferCommission();
        if (!mounted) {
          return;
        }

        _refreshBalances();
        await showReceipt(title: 'Transfer Successful');
        if (mounted) {
          _resetTransaction();
        }
      }
    } catch (error) {
      if (mounted) {
        _transactionListener.stop();
        await DialogService.error(context, message: error.toString());
      }
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  Future<void> _showWithdrawalQr() async {
    final state = ref.read(walletTransactionProvider);

    final user = getCurrentUser();

    final signedTransaction = await getSignedTransaction(
      v: "v10",
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

    _transactionListener.listenForTransactionStatus(
      reference: state.reference!,
      onTransactionSuccess: handleTransactionSuccess,
      onStatusChange: handleStatusChange,
    );

    final qrKey = GlobalKey();

    DialogService.transact(
      context,
      download: false,
      qrKey: qrKey,
      data: signedTransaction.transactionData,
      title: 'Scan to Withdraw Commission',
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

      _refreshBalances();

      await showReceipt(title: 'Withdrawal Successful');

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

  Future<bool?> _confirmTransaction({required bool withdraw}) {
    final state = ref.read(walletTransactionProvider);

    final currency = state.currency!.code;

    return DialogService.paymentConfirmation(
      context,
      title: withdraw ? 'Confirm Withdrawal' : 'Confirm Transfer',
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

  Future<void> showReceipt({required String title}) async {
    final state = ref.read(walletTransactionProvider);

    final currency = state.currency!.code;

    final screenRoute = ModalRoute.of(context);

    await DialogService.paymentReceipt(
      context,
      title: title,
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

  void _refreshBalances() {
    ref.invalidate(multiWalletSummaryProvider);
    refreshUserDashboard(ref);
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
