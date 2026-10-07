import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:ngoda/data_models/payment/payment_row.dart';
import 'package:ngoda/data_models/transaction/transaction_data.dart';
import 'package:ngoda/services/currency_service.dart';
import 'package:ngoda/services/dialog_service.dart';
import 'package:ngoda/services/number_format_service.dart';
import 'package:ngoda/services/snackbar_service.dart';
import 'package:ngoda/services/transaction_status_listener_service.dart';
import 'package:ngoda/ui/enums/enums.dart';
import 'package:ngoda/ui/extensions/app_size.dart';
import 'package:ngoda/ui/extensions/theme_extension.dart';
import 'package:ngoda/ui/functions/get_signed_transaction.dart';
import 'package:ngoda/ui/screens/finance/providers/transactions_config_provider.dart';
import 'package:ngoda/ui/screens/wallet/transactions/provider/wallet_transaction_provider.dart';
import 'package:ngoda/ui/shared/app_text_styles.dart';
import 'package:ngoda/ui/widgets/app_button.dart';
import 'package:ngoda/ui/widgets/app_error_state.dart';
import 'package:ngoda/ui/widgets/app_value_row.dart';
import 'package:ngoda/ui/widgets/input_field.dart';
import 'package:ngoda/ui/widgets/payment_calculation_card.dart';
import 'package:ngoda/ui/widgets/view_header.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class VoucherPaymentScreen extends ConsumerStatefulWidget {
  final TransactionData? qrData;

  const VoucherPaymentScreen({super.key, this.qrData});

  @override
  ConsumerState<VoucherPaymentScreen> createState() =>
      _VoucherPaymentScreenState();
}

class _VoucherPaymentScreenState extends ConsumerState<VoucherPaymentScreen> {
  final amountCtrl = TextEditingController();
  final voucherCtrl = TextEditingController();
  final currencyCtrl = TextEditingController();
  final emailCtrl = TextEditingController();

  late final TransactionStatusListenerService _transactionListener;

  bool _successHandled = false;

  @override
  void initState() {
    super.initState();

    /*
     * Always initialise the listener.
     *
     * The previous implementation initialised it
     * only when qrData was available, while
     * dispose() always attempted to stop it.
     */
    _transactionListener = TransactionStatusListenerService(
      supabase: Supabase.instance.client,
    );

    final data = widget.qrData;

    if (data == null) {
      return;
    }

    final voucherAmount = data.a / 100;

    voucherCtrl.text = NumberFormatService.formatAmount(
      voucherAmount,
      currency: data.c,
    );

    emailCtrl.text = data.s;
    currencyCtrl.text = data.c.toUpperCase();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }

      final currency = CurrencyService.get(data.c);

      if (currency == null) {
        return;
      }

      final notifier = ref.read(walletTransactionProvider.notifier);

      notifier.initReference();
      notifier.updateVoucherCurrency(currency);
    });
  }

  @override
  void dispose() {
    _transactionListener.stop();

    amountCtrl.dispose();
    voucherCtrl.dispose();
    currencyCtrl.dispose();
    emailCtrl.dispose();

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    final radius = context.radius;
    final colorScheme = context.colorScheme;

    final state = ref.watch(walletTransactionProvider);

    final data = widget.qrData;

    if (data == null) {
      return const Scaffold(
        body: SafeArea(child: AppErrorState(message: 'Failed to read QR')),
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
                  title: 'Merchant Payment',
                  subtitle: 'Make payment securely',
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
                            borderRadius: BorderRadius.circular(radius.md),
                            boxShadow: [
                              BoxShadow(
                                color: colorScheme.shadow.withValues(
                                  alpha: 0.05,
                                ),
                                blurRadius: spacing.lg,
                                offset: Offset(0, spacing.sm),
                              ),
                            ],
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              InputField(
                                controller: emailCtrl,
                                readOnly: true,
                                placeholder: 'User',
                              ),

                              SizedBox(height: spacing.md),

                              InputField(
                                controller: currencyCtrl,
                                readOnly: true,
                                placeholder: 'Currency',
                              ),

                              SizedBox(height: spacing.md),

                              InputField(
                                controller: voucherCtrl,
                                readOnly: true,
                                placeholder: 'Voucher Amount',
                              ),

                              SizedBox(height: spacing.md),

                              InputField(
                                controller: amountCtrl,
                                placeholder: 'Amount',
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                      decimal: true,
                                    ),
                                onChanged: _updateAmount,
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
                                      text: 'Pay',
                                      isProcessing: state.isLoading,
                                      onPressed:
                                          !state.isValid || state.isLoading
                                          ? null
                                          : handleMerchantPayment,
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

  void _updateAmount(String value) {
    final config = ref.read(transactionsConfigProvider).value;

    final currency = ref.read(walletTransactionProvider).currency;

    if (config == null || currency == null || config.error != null) {
      return;
    }

    final feeConfig = config.result?.get('merchant_payment', currency.code);

    if (feeConfig == null) {
      return;
    }

    ref
        .read(walletTransactionProvider.notifier)
        .updateAmountReceive(value, feeConfig: feeConfig);
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
          label: 'Total',
          value: NumberFormatService.formatAmount(
            state.totalDebit,
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

  Future<void> handleMerchantPayment() async {
    final voucher = widget.qrData;

    if (voucher == null) {
      return;
    }

    try {
      final state = ref.read(walletTransactionProvider);

      /*
       * Listen before submitting so a fast
       * backend status update cannot be missed.
       */
      _transactionListener.listenForTransactionStatus(
        reference: state.reference!,
        onTransactionSuccess: handleTransactionSuccess,
        onStatusChange: handleStatusChange,
      );

      final signedTransaction = await getSignedTransaction(
        v: 'v0',
        reference: state.reference!,
        identifier: voucher.r,
        amount: state.amount,
        feeAmount: state.feeAmount,
        taxAmount: 0,
        currency: state.currency!.code,
      );

      final notifier = ref.read(walletTransactionProvider.notifier);

      await notifier.merchantVoucherPayment(
        transaction: signedTransaction.transactionData,
        voucher: voucher,
      );

      if (!mounted) {
        return;
      }

      /*
       * The current notifier call completes the
       * payment synchronously from this screen's
       * perspective.
       *
       * The realtime listener can also report
       * success. _handleSuccessOnce prevents
       * duplicate receipts.
       */
      await _handleSuccessOnce();
    } catch (error) {
      _transactionListener.stop();

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
    await _handleSuccessOnce();
  }

  Future<void> _handleSuccessOnce() async {
    if (_successHandled || !mounted) {
      return;
    }

    _successHandled = true;
    _transactionListener.stop();

    try {
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

  Future<void> showReceipt() async {
    final state = ref.read(walletTransactionProvider);

    final currency = state.currency!.code;

    final screenRoute = ModalRoute.of(context);

    await DialogService.paymentReceipt(
      context,
      title: 'Payment Successful',
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

    _successHandled = false;
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
