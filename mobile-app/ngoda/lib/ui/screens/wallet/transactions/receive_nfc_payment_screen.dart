import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:ngoda/data_models/payment/payment_row.dart';
import 'package:ngoda/services/currency_service.dart';
import 'package:ngoda/services/dialog_service.dart';
import 'package:ngoda/services/number_format_service.dart';
import 'package:ngoda/services/snackbar_service.dart';
import 'package:ngoda/services/tap_reader_service.dart';
import 'package:ngoda/services/transaction_status_listener_service.dart';
import 'package:ngoda/ui/enums/enums.dart';
import 'package:ngoda/ui/extensions/app_size.dart';
import 'package:ngoda/ui/extensions/theme_extension.dart';
import 'package:ngoda/ui/functions/get_current_user.dart';
import 'package:ngoda/ui/functions/get_signed_transaction.dart';
import 'package:ngoda/ui/functions/get_wallet_balances.dart';
import 'package:ngoda/ui/functions/refresh_user_dashboard.dart';
import 'package:ngoda/ui/screens/finance/providers/transactions_config_provider.dart';
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

class ReceiveNFCPaymentScreen extends ConsumerStatefulWidget {
  const ReceiveNFCPaymentScreen({super.key});

  @override
  ConsumerState<ReceiveNFCPaymentScreen> createState() =>
      _ReceiveNFCPaymentScreenState();
}

class _ReceiveNFCPaymentScreenState
    extends ConsumerState<ReceiveNFCPaymentScreen> {
  final amountCtrl = TextEditingController();

  late final TransactionStatusListenerService _transactionListener;

  bool _successHandled = false;

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

    /*
     * dispose() cannot await, but NFC payload must
     * not remain active after leaving this screen.
     */
    TapReaderService.clearPayload();

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

    final balances = getMerchantWalletBalance(ref);

    if (balances == null) {
      return Scaffold(
        body: SafeArea(
          child: Padding(
            padding: EdgeInsets.all(spacing.md),
            child: Column(
              children: [
                ViewHeader(
                  title: 'Receive Payment',
                  subtitle: 'Receive payment securely from user',
                  onClose: _closeScreen,
                ),
                const Expanded(
                  child: AppErrorState(
                    message: 'Failed to get merchant wallet',
                  ),
                ),
              ],
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
                  title: 'Receive Payment',
                  subtitle: 'Receive payment securely from user',
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

                                  /*
                                   * Recalculate an
                                   * already-entered
                                   * amount when the
                                   * currency changes.
                                   */
                                  if (amountCtrl.text.trim().isNotEmpty) {
                                    _updateAmount(amountCtrl.text);
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
                                      text: 'Receive',
                                      isProcessing: state.isLoading,
                                      onPressed:
                                          !state.isValid || state.isLoading
                                          ? null
                                          : _confirmAndReceive,
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
          valueStyle: AppTextStyles.smallNumber(
            context,
          ).copyWith(fontWeight: FontWeight.w700),
          addBottomSpacing: false,
        ),
      ],
    );
  }

  Future<bool?> confirmPayment() {
    final state = ref.read(walletTransactionProvider);

    final currency = state.currency!.code;

    return DialogService.paymentConfirmation(
      context,
      title: 'Confirm Payment',
      rows: [
        PaymentRow(
          'Amount',
          NumberFormatService.formatAmount(state.amount, currency: currency),
          type: PaymentRowType.amount,
          isBold: true,
        ),
      ],
    );
  }

  Future<void> _confirmAndReceive() async {
    final confirmed = await confirmPayment();

    if (confirmed != true || !mounted) {
      return;
    }

    await handleReceivePayment();
  }

  Future<void> handleReceivePayment() async {
    try {
      final user = getCurrentUser();

      final state = ref.read(walletTransactionProvider);

      _successHandled = false;

      /*
     * Start listening before exposing the NFC
     * payload so that a fast payment cannot be
     * missed.
     */
      _transactionListener.listenForTransactionStatus(
        reference: state.reference!,
        onTransactionSuccess: handleTransactionSuccess,
        onStatusChange: handleStatusChange,
      );

      final signedTransaction = await getSignedTransaction(
        v: 'v4',
        reference: state.reference!,
        identifier: user.userId!,
        amount: state.amount,
        feeAmount: state.feeAmount,
        taxAmount: 0,
        currency: state.currency!.code,
      );

      await TapReaderService.setPayload(
        signedTransaction.transactionData.toJson(),
      );

      if (!mounted) {
        _transactionListener.stop();

        await TapReaderService.clearPayload();

        return;
      }

      /*
     * DialogService.nfcPayment returns void.
     *
     * Do not await it. The transaction lifecycle
     * continues through the realtime transaction
     * status listener.
     */
      DialogService.nfcPayment(
        context,
        data: signedTransaction.transactionData,
        onCancel: () async {
          _transactionListener.stop();

          await TapReaderService.clearPayload();

          if (!mounted) {
            return;
          }

          _resetTransaction();

          /*
         * Close the NFC payment dialog.
         */
          if (context.canPop()) {
            context.pop();
          }
        },
      );
    } catch (error) {
      _transactionListener.stop();

      await TapReaderService.clearPayload();

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
    if (_successHandled || !mounted) {
      return;
    }

    _successHandled = true;

    _transactionListener.stop();

    try {
      await TapReaderService.clearPayload();

      if (!mounted) {
        return;
      }

      /*
       * Close the active NFC payment dialog
       * before opening the receipt.
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
      await TapReaderService.clearPayload();

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

  Future<void> _closeScreen() async {
    if (!mounted) {
      return;
    }

    FocusScope.of(context).unfocus();

    _transactionListener.stop();

    await TapReaderService.clearPayload();

    if (!mounted) {
      return;
    }

    _resetTransaction();

    if (context.canPop()) {
      context.pop();
    }
  }
}
