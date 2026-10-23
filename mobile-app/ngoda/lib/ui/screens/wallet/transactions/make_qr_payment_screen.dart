import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:ngoda/data_models/payment/customer_transaction_setup.dart';
import 'package:ngoda/data_models/payment/payment_row.dart';
import 'package:ngoda/data_models/transaction/transaction_data.dart';
import 'package:ngoda/services/dialog_service.dart';
import 'package:ngoda/services/number_format_service.dart';
import 'package:ngoda/services/transaction_loyalty_celebration_service.dart';
import 'package:ngoda/ui/enums/enums.dart';
import 'package:ngoda/ui/screens/auth/providers/auth_provider.dart';
import 'package:ngoda/ui/extensions/app_size.dart';
import 'package:ngoda/ui/extensions/theme_extension.dart';
import 'package:ngoda/ui/functions/refresh_user_dashboard.dart';
import 'package:ngoda/ui/screens/wallet/transactions/provider/customer_transaction_setup_provider.dart';
import 'package:ngoda/ui/screens/wallet/transactions/provider/max_tap_payment_amount_provider.dart';
import 'package:ngoda/ui/screens/wallet/transactions/provider/wallet_transaction_provider.dart';
import 'package:ngoda/ui/shared/app_text_styles.dart';
import 'package:ngoda/ui/widgets/app_button.dart';
import 'package:ngoda/ui/widgets/app_error_state.dart';
import 'package:ngoda/ui/widgets/app_value_row.dart';
import 'package:ngoda/ui/widgets/input_field.dart';
import 'package:ngoda/ui/widgets/payment_calculation_card.dart';
import 'package:ngoda/ui/widgets/view_header.dart';

class MakeQrPaymentScreen extends ConsumerStatefulWidget {
  final TransactionData? qrData;

  const MakeQrPaymentScreen({super.key, this.qrData});

  @override
  ConsumerState<MakeQrPaymentScreen> createState() =>
      _MakeQrPaymentScreenState();
}

class _MakeQrPaymentScreenState extends ConsumerState<MakeQrPaymentScreen> {
  final amountCtrl = TextEditingController();
  final emailCtrl = TextEditingController();

  bool _transactionInitialized = false;
  bool _autoPaymentChecked = false;
  bool _paymentStarted = false;
  bool _autoEvaluationRunning = false;
  bool _autoCheckScheduled = false;

  double? _amount;
  String? _currencyCode;

  double get _optionalPaymentFee {
    final data = widget.qrData;

    if (data == null) {
      return 0;
    }

    return data.f / 100;
  }

  @override
  void initState() {
    super.initState();

    final data = widget.qrData;

    if (data == null) {
      return;
    }

    /*
     * Merchant payment QR contract:
     *
     * a = purchase amount
     * f = optional payment-fee quote
     *
     * The support contribution is opt-in.
     * It must therefore start disabled.
     */
    _amount = data.a / 100;
    _currencyCode = data.c;

    amountCtrl.text = NumberFormatService.formatAmount(
      _amount!,
      currency: _currencyCode!,
    );

    emailCtrl.text = data.s;

    _listenToWalletReadiness();
    _listenToTransactionSetup();
    _listenToPaymentLimit();
  }

  void _listenToTransactionSetup() {
    ref.listenManual<AsyncValue<CustomerTransactionSetup>>(
      customerTransactionSetupProvider,
      (previous, next) {
        _handleTransactionSetup(next);
      },
    );

    _handleTransactionSetup(ref.read(customerTransactionSetupProvider));
  }

  void _handleTransactionSetup(
    AsyncValue<CustomerTransactionSetup> setupAsync,
  ) {
    setupAsync.whenData((setup) {
      if (_transactionInitialized) {
        return;
      }

      final data = widget.qrData;
      final currencyCode = _currencyCode;

      if (data == null || currencyCode == null) {
        return;
      }

      final currency = setup.currencyRegistry.getByCode(currencyCode);

      if (currency == null) {
        return;
      }

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _transactionInitialized) {
          return;
        }

        ref.read(walletTransactionProvider.notifier)
          ..initReference()
          ..updateCurrency(currency, setup.balances)
          ..updateAmountPay(data)
          ..updatePaymentFeeContribution(data, paymentFeeContribution: false);

        _transactionInitialized = true;

        _scheduleAutoPaymentCheck();
      });
    });
  }

  void _listenToPaymentLimit() {
    ref.listenManual(maxTapPaymentAmountProvider, (previous, next) {
      if (next.hasValue) {
        _scheduleAutoPaymentCheck();
      }
    });

    if (ref.read(maxTapPaymentAmountProvider).hasValue) {
      _scheduleAutoPaymentCheck();
    }
  }

  void _listenToWalletReadiness() {
    ref.listenManual(walletTransactionProvider, (previous, next) {
      if (!mounted || _autoPaymentChecked || _paymentStarted) {
        return;
      }
      if (next.isValid && next.currency != null && !next.isLoading) {
        _scheduleAutoPaymentCheck();
      }
    });
  }

  void _scheduleAutoPaymentCheck() {
    if (!mounted ||
        _autoCheckScheduled ||
        _autoPaymentChecked ||
        _paymentStarted) {
      return;
    }
    _autoCheckScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _autoCheckScheduled = false;
      if (mounted) {
        unawaited(_tryAutoProcessPayment());
      }
    });
    // A callback registered after a frame must not wait for a user tap
    // to cause another frame.
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  Future<void> _tryAutoProcessPayment() async {
    if (!mounted ||
        !_transactionInitialized ||
        _autoPaymentChecked ||
        _paymentStarted ||
        _autoEvaluationRunning) {
      return;
    }
    final data = widget.qrData;
    final amount = _amount;
    if (data == null || amount == null) return;

    final state = ref.read(walletTransactionProvider);
    if (!state.isValid || state.currency == null || state.isLoading) return;
    if (state.reference != data.r.trim() ||
        state.currency!.code.trim().toLowerCase() !=
            data.c.trim().toLowerCase()) {
      return;
    }

    setState(() => _autoEvaluationRunning = true);
    try {
      final limitResponse = await ref
          .read(maxTapPaymentAmountProvider.future)
          .timeout(const Duration(seconds: 10));
      if (!mounted) return;
      if (limitResponse.error != null) {
        throw Exception(limitResponse.error.toString());
      }
      final limit = limitResponse.result?.getByCurrency(data.c)?.maxAmount;
      if (limit == null || !limit.isFinite || limit <= 0) {
        throw Exception(
          'Payment limit is unavailable for ${data.c.toUpperCase()}.',
        );
      }

      // Recheck after waiting: the wallet may have changed in the meantime.
      final ready = ref.read(walletTransactionProvider);
      if (!ready.isValid ||
          ready.currency == null ||
          ready.isLoading ||
          ready.reference != data.r.trim() ||
          ready.currency!.code.trim().toLowerCase() !=
              data.c.trim().toLowerCase()) {
        return;
      }
      _autoPaymentChecked = true;
      if (amount > limit) return; // Keep manual review above the limit.

      final auth = ref.read(authProvider);
      if (auth.isLocked) {
        await ref.read(authProvider.notifier).unlock();
        if (!mounted) return;
        if (ref.read(authProvider).isLocked) {
          _cancelPayment();
          return;
        }
      }
      if (!mounted) return;
      final current = ref.read(walletTransactionProvider);
      if (!current.isValid ||
          current.isLoading ||
          current.reference != data.r.trim() ||
          current.currency?.code.trim().toLowerCase() !=
              data.c.trim().toLowerCase()) {
        return;
      }

      // Automatic payment always starts without an optional contribution.
      ref
          .read(walletTransactionProvider.notifier)
          .updatePaymentFeeContribution(data, paymentFeeContribution: false);
      if (!ref.read(walletTransactionProvider).isValid) return;
      await _processMerchantPayment();
    } on TimeoutException {
      _autoPaymentChecked = true;
      if (mounted) {
        await DialogService.error(
          context,
          message: 'Unable to load payment limit.',
        );
      }
    } catch (error) {
      _autoPaymentChecked = true;
      if (mounted) {
        await DialogService.error(context, message: error.toString());
      }
    } finally {
      if (mounted) setState(() => _autoEvaluationRunning = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    final radius = context.radius;
    final colorScheme = context.colorScheme;

    final state = ref.watch(walletTransactionProvider);

    final setupAsync = ref.watch(customerTransactionSetupProvider);

    final data = widget.qrData;

    if (data == null) {
      return Scaffold(
        body: SafeArea(
          child: Padding(
            padding: EdgeInsets.all(spacing.md),
            child: Column(
              children: [
                ViewHeader(
                  title: 'Merchant Payment',
                  subtitle: 'Make payment securely',
                  onClose: _closeScreen,
                ),
                const Expanded(
                  child: AppErrorState(message: 'Failed to read payment QR'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    if (setupAsync.hasError) {
      return Scaffold(
        body: SafeArea(
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
                  child: Center(
                    child: Text(
                      setupAsync.error.toString(),
                      textAlign: TextAlign.center,
                      style: AppTextStyles.small(
                        context,
                      ).copyWith(color: colorScheme.error),
                    ),
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
                  title: 'Merchant Payment',
                  subtitle: 'Make payment securely',
                  onClose: _closeScreen,
                ),

                Expanded(
                  child: SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
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
                                placeholder: 'Merchant',
                              ),

                              SizedBox(height: spacing.md),

                              InputField(
                                controller: amountCtrl,
                                readOnly: true,
                                placeholder: 'Amount',
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
                                  state.amount > 0 &&
                                  _optionalPaymentFee > 0) ...[
                                SizedBox(height: spacing.lg),
                                _SupportNgodaTile(
                                  value: state.paymentFeeContribution,
                                  contributionAmount: _formattedOptionalFee(),
                                  enabled:
                                      !state.isLoading &&
                                      !_paymentStarted &&
                                      !_autoEvaluationRunning,
                                  onChanged: _changePaymentFeeContribution,
                                ),
                              ],

                              if (state.currency != null &&
                                  state.amount > 0) ...[
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
                                      isDisabled:
                                          state.isLoading ||
                                          _paymentStarted ||
                                          _autoEvaluationRunning,
                                      onPressed: _cancelPayment,
                                    ),
                                  ),

                                  SizedBox(width: spacing.md),

                                  Expanded(
                                    child: AppButton(
                                      text: 'Pay',
                                      isProcessing:
                                          state.isLoading ||
                                          _paymentStarted ||
                                          _autoEvaluationRunning,
                                      onPressed:
                                          !state.isValid ||
                                              state.isLoading ||
                                              _paymentStarted ||
                                              _autoEvaluationRunning
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

  String _formattedOptionalFee() {
    final state = ref.read(walletTransactionProvider);

    final currency = state.currency?.code;

    if (currency == null) {
      return '';
    }

    return NumberFormatService.formatAmount(
      _optionalPaymentFee,
      currency: currency,
    );
  }

  void _changePaymentFeeContribution(bool value) {
    final data = widget.qrData;

    if (data == null ||
        _autoEvaluationRunning ||
        _paymentStarted ||
        ref.read(walletTransactionProvider).isLoading) {
      return;
    }

    ref
        .read(walletTransactionProvider.notifier)
        .updatePaymentFeeContribution(data, paymentFeeContribution: value);
  }

  Future<void> handleMerchantPayment() async {
    if (!mounted || _paymentStarted || _autoEvaluationRunning) {
      return;
    }

    final data = widget.qrData;
    final amount = _amount;

    if (data == null || amount == null) {
      return;
    }

    final currencyLimit = ref
        .read(maxTapPaymentAmountProvider)
        .value
        ?.result
        ?.getByCurrency(data.c)
        ?.maxAmount;

    if (currencyLimit == null) {
      await DialogService.error(
        context,
        message: 'Payment limit is unavailable',
      );

      return;
    }

    /*
     * Above the configured maximum requires
     * explicit user confirmation.
     */
    if (amount > currencyLimit) {
      final confirmed = await confirmMerchantPayment();

      if (confirmed != true) {
        return;
      }
    }

    await _processMerchantPayment();
  }

  Future<void> _processMerchantPayment() async {
    if (_paymentStarted) {
      return;
    }

    final data = widget.qrData;

    if (data == null) {
      return;
    }

    setState(() {
      _paymentStarted = true;
    });

    try {
      final notifier = ref.read(walletTransactionProvider.notifier);

      await notifier.merchantPayment(transaction: data);

      final loyaltyResult = ref.read(walletTransactionProvider).loyaltyResult;

      refreshUserDashboard(ref);

      if (!mounted) {
        return;
      }

      await showReceipt();

      if (!mounted) {
        return;
      }

      /*
       * Close the payment screen before showing
       * the loyalty celebration.
       */
      if (context.canPop()) {
        context.pop();
      }

      await TransactionLoyaltyCelebrationService.show(context, loyaltyResult);

      amountCtrl.clear();
      emailCtrl.clear();

      notifier.reset();
    } catch (error) {
      if (!mounted) {
        return;
      }

      await DialogService.error(context, message: error.toString());
    } finally {
      if (mounted) {
        setState(() {
          _paymentStarted = false;
        });
      }
    }
  }

  Future<bool?> confirmMerchantPayment() {
    final state = ref.read(walletTransactionProvider);

    final currency = state.currency?.code;

    if (currency == null) {
      return Future.value(false);
    }

    return DialogService.paymentConfirmation(
      context,
      title: 'Confirm Merchant Payment',
      rows: [
        PaymentRow(
          'Amount',
          NumberFormatService.formatAmount(state.amount, currency: currency),
          type: PaymentRowType.amount,
        ),
        if (state.paymentFeeContribution)
          PaymentRow(
            'Support contribution',
            NumberFormatService.formatAmount(
              state.feeAmount,
              currency: currency,
            ),
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
    );
  }

  Widget _buildCalculation() {
    final state = ref.watch(walletTransactionProvider);

    final currency = state.currency?.code;

    if (currency == null) {
      return const SizedBox.shrink();
    }

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

        if (state.paymentFeeContribution) ...[
          SizedBox(height: context.spacing.sm),
          AppValueRow(
            label: 'Support contribution',
            value: NumberFormatService.formatAmount(
              state.feeAmount,
              currency: currency,
            ),
            addBottomSpacing: false,
          ),
        ],

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

  Future<void> showReceipt() async {
    final state = ref.read(walletTransactionProvider);

    final currency = state.currency?.code;

    if (currency == null) {
      return;
    }

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
        if (state.paymentFeeContribution)
          PaymentRow(
            'Support contribution',
            NumberFormatService.formatAmount(
              state.feeAmount,
              currency: currency,
            ),
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

  void _cancelPayment() {
    if (!mounted) {
      return;
    }

    amountCtrl.clear();
    emailCtrl.clear();

    ref.read(walletTransactionProvider.notifier).reset();

    if (context.canPop()) {
      context.pop();
    }
  }

  void _closeScreen() {
    if (_paymentStarted || _autoEvaluationRunning) {
      return;
    }

    _cancelPayment();
  }

  @override
  void dispose() {
    amountCtrl.dispose();
    emailCtrl.dispose();

    super.dispose();
  }
}

class _SupportNgodaTile extends StatelessWidget {
  final bool value;
  final String contributionAmount;
  final bool enabled;
  final ValueChanged<bool> onChanged;

  const _SupportNgodaTile({
    required this.value,
    required this.contributionAmount,
    required this.enabled,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    final radius = context.radius;
    final colorScheme = context.colorScheme;

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: colorScheme.primary.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(radius.md),
        border: Border.all(color: colorScheme.primary.withValues(alpha: 0.18)),
      ),
      child: SwitchListTile.adaptive(
        value: value,
        onChanged: enabled ? onChanged : null,
        contentPadding: EdgeInsets.symmetric(
          horizontal: spacing.md,
          vertical: spacing.xs,
        ),
        title: Text(
          'Support Ngoda ecosystem',
          style: AppTextStyles.small(
            context,
          ).copyWith(fontWeight: FontWeight.w700),
        ),
        subtitle: Text(
          value
              ? '$contributionAmount will be added to this payment. '
                    'You will also earn bonus points.'
              : 'Optional. Add $contributionAmount and earn bonus points.',
          style: AppTextStyles.tiny(context),
        ),
      ),
    );
  }
}

// import 'dart:async';

// import 'package:flutter/material.dart';
// import 'package:flutter_riverpod/flutter_riverpod.dart';
// import 'package:go_router/go_router.dart';
// import 'package:ngoda/data_models/payment/customer_transaction_setup.dart';
// import 'package:ngoda/data_models/payment/payment_row.dart';
// import 'package:ngoda/data_models/transaction/transaction_data.dart';
// import 'package:ngoda/services/dialog_service.dart';
// import 'package:ngoda/services/number_format_service.dart';
// import 'package:ngoda/services/transaction_loyalty_celebration_service.dart';
// import 'package:ngoda/ui/enums/enums.dart';
// import 'package:ngoda/ui/extensions/app_size.dart';
// import 'package:ngoda/ui/extensions/theme_extension.dart';
// import 'package:ngoda/ui/functions/refresh_user_dashboard.dart';
// import 'package:ngoda/ui/screens/wallet/transactions/provider/customer_transaction_setup_provider.dart';
// import 'package:ngoda/ui/screens/wallet/transactions/provider/max_tap_payment_amount_provider.dart';
// import 'package:ngoda/ui/screens/wallet/transactions/provider/wallet_transaction_provider.dart';
// import 'package:ngoda/ui/shared/app_text_styles.dart';
// import 'package:ngoda/ui/widgets/app_button.dart';
// import 'package:ngoda/ui/widgets/app_error_state.dart';
// import 'package:ngoda/ui/widgets/app_value_row.dart';
// import 'package:ngoda/ui/widgets/input_field.dart';
// import 'package:ngoda/ui/widgets/payment_calculation_card.dart';
// import 'package:ngoda/ui/widgets/view_header.dart';

// class MakeQrPaymentScreen extends ConsumerStatefulWidget {
//   final TransactionData? qrData;

//   const MakeQrPaymentScreen({super.key, this.qrData});

//   @override
//   ConsumerState<MakeQrPaymentScreen> createState() =>
//       _MakeQrPaymentScreenState();
// }

// class _MakeQrPaymentScreenState extends ConsumerState<MakeQrPaymentScreen> {
//   final amountCtrl = TextEditingController();
//   final emailCtrl = TextEditingController();

//   bool _transactionInitialized = false;
//   bool _autoPaymentChecked = false;
//   bool _paymentStarted = false;

//   double? _amount;
//   String? _currencyCode;

//   double get _optionalPaymentFee {
//     final data = widget.qrData;

//     if (data == null) {
//       return 0;
//     }

//     return data.f / 100;
//   }

//   @override
//   void initState() {
//     super.initState();

//     final data = widget.qrData;

//     if (data == null) {
//       return;
//     }

//     /*
//      * Merchant payment QR contract:
//      *
//      * a = purchase amount
//      * f = optional payment-fee quote
//      *
//      * The support contribution is opt-in.
//      * It must therefore start disabled.
//      */
//     _amount = data.a / 100;
//     _currencyCode = data.c;

//     amountCtrl.text = NumberFormatService.formatAmount(
//       _amount!,
//       currency: _currencyCode!,
//     );

//     emailCtrl.text = data.s;

//     _listenToTransactionSetup();
//     _listenToPaymentLimit();
//   }

//   void _listenToTransactionSetup() {
//     ref.listenManual<AsyncValue<CustomerTransactionSetup>>(
//       customerTransactionSetupProvider,
//       (previous, next) {
//         _handleTransactionSetup(next);
//       },
//     );

//     _handleTransactionSetup(ref.read(customerTransactionSetupProvider));
//   }

//   void _handleTransactionSetup(
//     AsyncValue<CustomerTransactionSetup> setupAsync,
//   ) {
//     setupAsync.whenData((setup) {
//       if (_transactionInitialized) {
//         return;
//       }

//       final data = widget.qrData;
//       final currencyCode = _currencyCode;

//       if (data == null || currencyCode == null) {
//         return;
//       }

//       final currency = setup.currencyRegistry.getByCode(currencyCode);

//       if (currency == null) {
//         return;
//       }

//       WidgetsBinding.instance.addPostFrameCallback((_) {
//         if (!mounted || _transactionInitialized) {
//           return;
//         }

//         ref.read(walletTransactionProvider.notifier)
//           ..initReference()
//           ..updateCurrency(currency, setup.balances)
//           ..updateAmountPay(data)
//           ..updatePaymentFeeContribution(data, paymentFeeContribution: false);

//         _transactionInitialized = true;

//         WidgetsBinding.instance.addPostFrameCallback((_) {
//           if (mounted) {
//             _tryAutoProcessPayment();
//           }
//         });
//       });
//     });
//   }

//   void _listenToPaymentLimit() {
//     ref.listenManual(maxTapPaymentAmountProvider, (previous, next) {
//       if (next.hasValue) {
//         _scheduleAutoPaymentCheck();
//       }
//     });

//     if (ref.read(maxTapPaymentAmountProvider).hasValue) {
//       _scheduleAutoPaymentCheck();
//     }
//   }

//   void _scheduleAutoPaymentCheck() {
//     WidgetsBinding.instance.addPostFrameCallback((_) {
//       if (mounted) {
//         _tryAutoProcessPayment();
//       }
//     });
//   }

//   Future<void> _tryAutoProcessPayment() async {
//     if (!_transactionInitialized || _autoPaymentChecked || _paymentStarted) {
//       return;
//     }

//     final data = widget.qrData;
//     final amount = _amount;

//     if (data == null || amount == null) {
//       return;
//     }

//     final currencyLimit = ref
//         .read(maxTapPaymentAmountProvider)
//         .value
//         ?.result
//         ?.getByCurrency(data.c)
//         ?.maxAmount;

//     if (currencyLimit == null) {
//       return;
//     }

//     final transactionState = ref.read(walletTransactionProvider);

//     if (!transactionState.isValid ||
//         transactionState.currency == null ||
//         transactionState.isLoading) {
//       return;
//     }

//     _autoPaymentChecked = true;

//     /*
//      * Payments at or below the configured limit
//      * are processed automatically.
//      *
//      * Support remains disabled because the user
//      * has not opted in.
//      */
//     if (amount <= currencyLimit) {
//       await _processMerchantPayment();
//     }
//   }

//   @override
//   Widget build(BuildContext context) {
//     final spacing = context.spacing;
//     final radius = context.radius;
//     final colorScheme = context.colorScheme;

//     final state = ref.watch(walletTransactionProvider);

//     final setupAsync = ref.watch(customerTransactionSetupProvider);

//     final data = widget.qrData;

//     if (data == null) {
//       return Scaffold(
//         body: SafeArea(
//           child: Padding(
//             padding: EdgeInsets.all(spacing.md),
//             child: Column(
//               children: [
//                 ViewHeader(
//                   title: 'Merchant Payment',
//                   subtitle: 'Make payment securely',
//                   onClose: _closeScreen,
//                 ),
//                 const Expanded(
//                   child: AppErrorState(message: 'Failed to read payment QR'),
//                 ),
//               ],
//             ),
//           ),
//         ),
//       );
//     }

//     if (setupAsync.hasError) {
//       return Scaffold(
//         body: SafeArea(
//           child: Padding(
//             padding: EdgeInsets.all(spacing.md),
//             child: Column(
//               children: [
//                 ViewHeader(
//                   title: 'Merchant Payment',
//                   subtitle: 'Make payment securely',
//                   onClose: _closeScreen,
//                 ),
//                 Expanded(
//                   child: Center(
//                     child: Text(
//                       setupAsync.error.toString(),
//                       textAlign: TextAlign.center,
//                       style: AppTextStyles.small(
//                         context,
//                       ).copyWith(color: colorScheme.error),
//                     ),
//                   ),
//                 ),
//               ],
//             ),
//           ),
//         ),
//       );
//     }

//     return Scaffold(
//       body: SafeArea(
//         child: GestureDetector(
//           behavior: HitTestBehavior.translucent,
//           onTap: () {
//             FocusScope.of(context).unfocus();
//           },
//           child: Padding(
//             padding: EdgeInsets.all(spacing.md),
//             child: Column(
//               children: [
//                 ViewHeader(
//                   title: 'Merchant Payment',
//                   subtitle: 'Make payment securely',
//                   onClose: _closeScreen,
//                 ),

//                 Expanded(
//                   child: SingleChildScrollView(
//                     physics: const AlwaysScrollableScrollPhysics(),
//                     keyboardDismissBehavior:
//                         ScrollViewKeyboardDismissBehavior.onDrag,
//                     child: Column(
//                       children: [
//                         SizedBox(height: spacing.md),

//                         Container(
//                           width: double.infinity,
//                           padding: EdgeInsets.all(spacing.md),
//                           decoration: BoxDecoration(
//                             color: context.theme.cardColor,
//                             borderRadius: BorderRadius.circular(radius.md),
//                             boxShadow: [
//                               BoxShadow(
//                                 color: colorScheme.shadow.withValues(
//                                   alpha: 0.05,
//                                 ),
//                                 blurRadius: spacing.lg,
//                                 offset: Offset(0, spacing.sm),
//                               ),
//                             ],
//                           ),
//                           child: Column(
//                             crossAxisAlignment: CrossAxisAlignment.start,
//                             children: [
//                               InputField(
//                                 controller: emailCtrl,
//                                 readOnly: true,
//                                 placeholder: 'Merchant',
//                               ),

//                               SizedBox(height: spacing.md),

//                               InputField(
//                                 controller: amountCtrl,
//                                 readOnly: true,
//                                 placeholder: 'Amount',
//                               ),

//                               if (state.error != null &&
//                                   state.error!.trim().isNotEmpty) ...[
//                                 SizedBox(height: spacing.sm),
//                                 Align(
//                                   alignment: Alignment.centerLeft,
//                                   child: Text(
//                                     state.error!,
//                                     style: AppTextStyles.tiny(
//                                       context,
//                                     ).copyWith(color: colorScheme.error),
//                                   ),
//                                 ),
//                               ],

//                               if (state.currency != null &&
//                                   state.amount > 0 &&
//                                   _optionalPaymentFee > 0) ...[
//                                 SizedBox(height: spacing.lg),
//                                 _SupportNgodaTile(
//                                   value: state.paymentFeeContribution,
//                                   contributionAmount: _formattedOptionalFee(),
//                                   enabled: !state.isLoading && !_paymentStarted,
//                                   onChanged: _changePaymentFeeContribution,
//                                 ),
//                               ],

//                               if (state.currency != null &&
//                                   state.amount > 0) ...[
//                                 SizedBox(height: spacing.md),
//                                 _buildCalculation(),
//                               ],

//                               SizedBox(height: spacing.lg),

//                               Row(
//                                 children: [
//                                   Expanded(
//                                     child: AppButton(
//                                       text: 'Cancel',
//                                       isPrimary: false,
//                                       isDisabled:
//                                           state.isLoading || _paymentStarted,
//                                       onPressed: _cancelPayment,
//                                     ),
//                                   ),

//                                   SizedBox(width: spacing.md),

//                                   Expanded(
//                                     child: AppButton(
//                                       text: 'Pay',
//                                       isProcessing:
//                                           state.isLoading || _paymentStarted,
//                                       onPressed:
//                                           !state.isValid ||
//                                               state.isLoading ||
//                                               _paymentStarted
//                                           ? null
//                                           : handleMerchantPayment,
//                                     ),
//                                   ),
//                                 ],
//                               ),
//                             ],
//                           ),
//                         ),

//                         SizedBox(height: spacing.md),
//                       ],
//                     ),
//                   ),
//                 ),
//               ],
//             ),
//           ),
//         ),
//       ),
//     );
//   }

//   String _formattedOptionalFee() {
//     final state = ref.read(walletTransactionProvider);

//     final currency = state.currency?.code;

//     if (currency == null) {
//       return '';
//     }

//     return NumberFormatService.formatAmount(
//       _optionalPaymentFee,
//       currency: currency,
//     );
//   }

//   void _changePaymentFeeContribution(bool value) {
//     final data = widget.qrData;

//     if (data == null ||
//         _paymentStarted ||
//         ref.read(walletTransactionProvider).isLoading) {
//       return;
//     }

//     ref
//         .read(walletTransactionProvider.notifier)
//         .updatePaymentFeeContribution(data, paymentFeeContribution: value);
//   }

//   Future<void> handleMerchantPayment() async {
//     if (_paymentStarted) {
//       return;
//     }

//     final data = widget.qrData;
//     final amount = _amount;

//     if (data == null || amount == null) {
//       return;
//     }

//     final currencyLimit = ref
//         .read(maxTapPaymentAmountProvider)
//         .value
//         ?.result
//         ?.getByCurrency(data.c)
//         ?.maxAmount;

//     if (currencyLimit == null) {
//       await DialogService.error(
//         context,
//         message: 'Payment limit is unavailable',
//       );

//       return;
//     }

//     /*
//      * Above the configured maximum requires
//      * explicit user confirmation.
//      */
//     if (amount > currencyLimit) {
//       final confirmed = await confirmMerchantPayment();

//       if (confirmed != true) {
//         return;
//       }
//     }

//     await _processMerchantPayment();
//   }

//   Future<void> _processMerchantPayment() async {
//     if (_paymentStarted) {
//       return;
//     }

//     final data = widget.qrData;

//     if (data == null) {
//       return;
//     }

//     setState(() {
//       _paymentStarted = true;
//     });

//     try {
//       final notifier = ref.read(walletTransactionProvider.notifier);

//       await notifier.merchantPayment(transaction: data);

//       final loyaltyResult = ref.read(walletTransactionProvider).loyaltyResult;

//       refreshUserDashboard(ref);

//       if (!mounted) {
//         return;
//       }

//       await showReceipt();

//       if (!mounted) {
//         return;
//       }

//       /*
//        * Close the payment screen before showing
//        * the loyalty celebration.
//        */
//       if (context.canPop()) {
//         context.pop();
//       }

//       await TransactionLoyaltyCelebrationService.show(context, loyaltyResult);

//       amountCtrl.clear();
//       emailCtrl.clear();

//       notifier.reset();
//     } catch (error) {
//       if (!mounted) {
//         return;
//       }

//       await DialogService.error(context, message: error.toString());
//     } finally {
//       if (mounted) {
//         setState(() {
//           _paymentStarted = false;
//         });
//       }
//     }
//   }

//   Future<bool?> confirmMerchantPayment() {
//     final state = ref.read(walletTransactionProvider);

//     final currency = state.currency?.code;

//     if (currency == null) {
//       return Future.value(false);
//     }

//     return DialogService.paymentConfirmation(
//       context,
//       title: 'Confirm Merchant Payment',
//       rows: [
//         PaymentRow(
//           'Amount',
//           NumberFormatService.formatAmount(state.amount, currency: currency),
//           type: PaymentRowType.amount,
//         ),
//         if (state.paymentFeeContribution)
//           PaymentRow(
//             'Support contribution',
//             NumberFormatService.formatAmount(
//               state.feeAmount,
//               currency: currency,
//             ),
//             type: PaymentRowType.amount,
//           ),
//         PaymentRow(
//           'Total',
//           NumberFormatService.formatAmount(
//             state.totalDebit,
//             currency: currency,
//           ),
//           type: PaymentRowType.amount,
//           isBold: true,
//         ),
//       ],
//     );
//   }

//   Widget _buildCalculation() {
//     final state = ref.watch(walletTransactionProvider);

//     final currency = state.currency?.code;

//     if (currency == null) {
//       return const SizedBox.shrink();
//     }

//     return PaymentCalculationCard(
//       children: [
//         AppValueRow(
//           label: 'Amount',
//           value: NumberFormatService.formatAmount(
//             state.amount,
//             currency: currency,
//           ),
//           addBottomSpacing: false,
//         ),

//         if (state.paymentFeeContribution) ...[
//           SizedBox(height: context.spacing.sm),
//           AppValueRow(
//             label: 'Support contribution',
//             value: NumberFormatService.formatAmount(
//               state.feeAmount,
//               currency: currency,
//             ),
//             addBottomSpacing: false,
//           ),
//         ],

//         Padding(
//           padding: EdgeInsets.symmetric(vertical: context.spacing.sm),
//           child: const Divider(),
//         ),

//         AppValueRow(
//           label: 'Total',
//           value: NumberFormatService.formatAmount(
//             state.totalDebit,
//             currency: currency,
//           ),
//           valueStyle: AppTextStyles.smallNumber(
//             context,
//           ).copyWith(fontWeight: FontWeight.w700),
//           addBottomSpacing: false,
//         ),
//       ],
//     );
//   }

//   Future<void> showReceipt() async {
//     final state = ref.read(walletTransactionProvider);

//     final currency = state.currency?.code;

//     if (currency == null) {
//       return;
//     }

//     final screenRoute = ModalRoute.of(context);

//     await DialogService.paymentReceipt(
//       context,
//       title: 'Payment Successful',
//       rows: [
//         PaymentRow(
//           'Amount',
//           NumberFormatService.formatAmount(state.amount, currency: currency),
//           type: PaymentRowType.amount,
//         ),
//         if (state.paymentFeeContribution)
//           PaymentRow(
//             'Support contribution',
//             NumberFormatService.formatAmount(
//               state.feeAmount,
//               currency: currency,
//             ),
//             type: PaymentRowType.amount,
//           ),
//         PaymentRow(
//           'Total',
//           NumberFormatService.formatAmount(
//             state.totalDebit,
//             currency: currency,
//           ),
//           type: PaymentRowType.amount,
//           isBold: true,
//         ),
//       ],
//       onDone: () {},
//     );

//     await WidgetsBinding.instance.endOfFrame;

//     while (mounted && screenRoute != null && !screenRoute.isCurrent) {
//       await WidgetsBinding.instance.endOfFrame;
//     }

//     await Future<void>.delayed(const Duration(milliseconds: 200));
//   }

//   void _cancelPayment() {
//     if (!mounted) {
//       return;
//     }

//     amountCtrl.clear();
//     emailCtrl.clear();

//     ref.read(walletTransactionProvider.notifier).reset();

//     if (context.canPop()) {
//       context.pop();
//     }
//   }

//   void _closeScreen() {
//     if (_paymentStarted) {
//       return;
//     }

//     _cancelPayment();
//   }

//   @override
//   void dispose() {
//     amountCtrl.dispose();
//     emailCtrl.dispose();

//     super.dispose();
//   }
// }

// class _SupportNgodaTile extends StatelessWidget {
//   final bool value;
//   final String contributionAmount;
//   final bool enabled;
//   final ValueChanged<bool> onChanged;

//   const _SupportNgodaTile({
//     required this.value,
//     required this.contributionAmount,
//     required this.enabled,
//     required this.onChanged,
//   });

//   @override
//   Widget build(BuildContext context) {
//     final spacing = context.spacing;
//     final radius = context.radius;
//     final colorScheme = context.colorScheme;

//     return Container(
//       width: double.infinity,
//       decoration: BoxDecoration(
//         color: colorScheme.primary.withValues(alpha: 0.06),
//         borderRadius: BorderRadius.circular(radius.md),
//         border: Border.all(color: colorScheme.primary.withValues(alpha: 0.18)),
//       ),
//       child: SwitchListTile.adaptive(
//         value: value,
//         onChanged: enabled ? onChanged : null,
//         contentPadding: EdgeInsets.symmetric(
//           horizontal: spacing.md,
//           vertical: spacing.xs,
//         ),
//         title: Text(
//           'Support Ngoda ecosystem',
//           style: AppTextStyles.small(
//             context,
//           ).copyWith(fontWeight: FontWeight.w700),
//         ),
//         subtitle: Text(
//           value
//               ? '$contributionAmount will be added to this payment. '
//                     'You will also earn bonus points.'
//               : 'Optional. Add $contributionAmount and earn bonus points.',
//           style: AppTextStyles.tiny(context),
//         ),
//       ),
//     );
//   }
// }
