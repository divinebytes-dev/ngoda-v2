import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:ngoda/data_models/payment/payment_row.dart';
import 'package:ngoda/data_models/transaction/transaction_data.dart';
import 'package:ngoda/services/dialog_service.dart';
import 'package:ngoda/services/number_format_service.dart';
import 'package:ngoda/services/transaction_loyalty_celebration_service.dart';
import 'package:ngoda/ui/enums/enums.dart';
import 'package:ngoda/ui/extensions/app_size.dart';
import 'package:ngoda/ui/extensions/theme_extension.dart';
import 'package:ngoda/ui/screens/auth/providers/auth_provider.dart';
import 'package:ngoda/ui/screens/customer/provider/customer_dashboard_provider.dart';
import 'package:ngoda/ui/screens/gamification/provider/loyalty_summary_provider.dart';
import 'package:ngoda/ui/screens/wallet/transactions/provider/max_tap_payment_amount_provider.dart';
import 'package:ngoda/ui/screens/wallet/transactions/provider/tap_payment_provider.dart';
import 'package:ngoda/ui/screens/wallet/transactions/provider/wallet_transaction_provider.dart';
import 'package:ngoda/ui/shared/app_colors.dart';
import 'package:ngoda/ui/shared/app_text_styles.dart';
import 'package:ngoda/ui/widgets/app_button.dart';
import 'package:ngoda/ui/widgets/app_value_row.dart';
import 'package:ngoda/ui/widgets/payment_calculation_card.dart';
import 'package:ngoda/ui/widgets/view_header.dart';

class MakeNFCPaymentScreen extends ConsumerStatefulWidget {
  final TransactionData? paymentData;

  const MakeNFCPaymentScreen({super.key, this.paymentData});

  @override
  ConsumerState<MakeNFCPaymentScreen> createState() =>
      _MakeNFCPaymentScreenState();
}

class _MakeNFCPaymentScreenState extends ConsumerState<MakeNFCPaymentScreen> {
  TapPaymentState paymentState = TapPaymentState.waiting;

  TransactionData? _paymentData;

  bool isProcessing = false;

  /*
   * Prevent the same payment from being
   * evaluated more than once at the same time.
   */
  bool _isEvaluatingPayment = false;

  /*
   * Prevent automatic approval from starting
   * more than once.
   */
  bool _autoApprovalStarted = false;

  /*
   * Prevent duplicate screen close operations.
   */
  bool _isClosing = false;

  ProviderSubscription<TransactionData?>? _paymentSubscription;

  @override
  @override
  void initState() {
    super.initState();

    _paymentData = widget.paymentData ?? ref.read(tapPaymentProvider);

    final initialPayment = _paymentData;

    if (initialPayment != null) {
      paymentState = TapPaymentState.processing;
    }

    _listenForPayments();

    /*
   * Provider state must not be modified while this
   * screen is being mounted.
   *
   * NFC can navigate to this screen while Flutter is
   * still building the route transition. Updating
   * walletTransactionProvider synchronously from
   * initState would therefore cause Riverpod to throw:
   *
   * "Tried to modify a provider while the widget tree
   * was building."
   *
   * Wait until the first frame has completed before
   * initializing and evaluating the NFC payment.
   */
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _isClosing) {
        return;
      }

      final payment = _paymentData;

      if (payment == null) {
        return;
      }

      /*
     * Every NFC payment starts without the optional
     * Ngoda support contribution.
     */
      _setPaymentFeeContribution(payment, false);

      unawaited(_evaluatePayment(payment));
    });
  }

  @override
  void dispose() {
    _paymentSubscription?.close();

    super.dispose();
  }

  void _listenForPayments() {
    _paymentSubscription = ref.listenManual<TransactionData?>(
      tapPaymentProvider,
      (previous, next) {
        if (!mounted || _isClosing || next == null) {
          return;
        }

        if (_isSamePayment(_paymentData, next)) {
          return;
        }

        if (isProcessing || _autoApprovalStarted || _isEvaluatingPayment) {
          return;
        }

        _receivePayment(next);
      },
    );
  }

  void _receivePayment(TransactionData payment) {
    if (!mounted ||
        _isClosing ||
        isProcessing ||
        _autoApprovalStarted ||
        _isEvaluatingPayment) {
      return;
    }

    _setPaymentFeeContribution(payment, false);

    setState(() {
      _paymentData = payment;

      paymentState = TapPaymentState.processing;
    });

    unawaited(_evaluatePayment(payment));
  }

  void _setPaymentFeeContribution(TransactionData payment, bool value) {
    ref
        .read(walletTransactionProvider.notifier)
        .updatePaymentFeeContribution(payment, paymentFeeContribution: value);
  }

  void _changePaymentFeeContribution(TransactionData payment, bool value) {
    if (isProcessing ||
        _isClosing ||
        paymentState != TapPaymentState.detected) {
      return;
    }

    _setPaymentFeeContribution(payment, value);
  }

  bool _isSamePayment(TransactionData? current, TransactionData next) {
    if (current == null) {
      return false;
    }

    if (current.r.isNotEmpty && next.r.isNotEmpty) {
      return current.r == next.r;
    }

    return current.c == next.c &&
        current.a == next.a &&
        current.f == next.f &&
        current.s == next.s;
  }

  @override
  Widget build(BuildContext context) {
    /*
     * Rebuild the detected-state calculation
     * when the contribution switch changes.
     */
    ref.watch(walletTransactionProvider);

    final spacing = context.spacing;

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: EdgeInsets.all(spacing.md),
          child: Column(
            children: [
              ViewHeader(
                title: 'Tap To Pay',
                subtitle: _subtitle(),
                onClose: _closeScreen,
              ),
              Expanded(child: _buildBody()),
            ],
          ),
        ),
      ),
    );
  }

  String _subtitle() {
    switch (paymentState) {
      case TapPaymentState.waiting:
        return 'Tap merchant phone';

      case TapPaymentState.detected:
        return 'Review payment';

      case TapPaymentState.processing:
        return 'Processing payment';

      case TapPaymentState.success:
        return 'Payment successful';

      case TapPaymentState.failed:
        return 'Payment failed';
    }
  }

  Widget _buildBody() {
    switch (paymentState) {
      case TapPaymentState.waiting:
        return _buildWaitingState();

      case TapPaymentState.detected:
        final payment = _paymentData;

        if (payment == null) {
          return _buildWaitingState();
        }

        return _buildDetectedState(payment);

      case TapPaymentState.processing:
        return _buildLoadingState();

      case TapPaymentState.success:
        return _buildSuccessState();

      case TapPaymentState.failed:
        return _buildFailedState();
    }
  }

  Widget _buildWaitingState() {
    final spacing = context.spacing;
    final iconSize = context.iconSize;
    final colorScheme = context.colorScheme;

    return Center(
      key: const ValueKey('waiting'),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: EdgeInsets.all(spacing.xl),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: colorScheme.primary.withValues(alpha: 0.08),
            ),
            child: Icon(
              Icons.nfc,
              size: iconSize.large,
              color: AppColors.darkPrimary,
            ),
          ),

          SizedBox(height: spacing.md),

          Text(
            'Ready To Scan',
            style: AppTextStyles.medium(
              context,
            ).copyWith(fontWeight: FontWeight.w700),
          ),

          SizedBox(height: spacing.xs),

          Text(
            'Tap merchant device to continue',
            textAlign: TextAlign.center,
            style: AppTextStyles.small(context),
          ),
        ],
      ),
    );
  }

  Widget _buildDetectedState(TransactionData request) {
    final spacing = context.spacing;
    final radius = context.radius;
    final iconSize = context.iconSize;
    final colorScheme = context.colorScheme;

    final transactionState = ref.watch(walletTransactionProvider);

    final amount = request.a / 100;

    final optionalFee = request.f / 100;

    final contributionSelected = transactionState.paymentFeeContribution;

    final appliedFee = contributionSelected ? optionalFee : 0.0;

    final total = amount + appliedFee;

    return SingleChildScrollView(
      key: ValueKey(
        'payment-'
        '${request.c}-'
        '${request.a}-'
        '${request.f}-'
        '${request.s}',
      ),
      physics: const AlwaysScrollableScrollPhysics(),
      child: Container(
        width: double.infinity,
        padding: EdgeInsets.all(spacing.md),
        margin: EdgeInsets.only(top: spacing.md, bottom: spacing.md),
        decoration: BoxDecoration(
          color: context.theme.cardColor,
          borderRadius: BorderRadius.circular(radius.md),
          boxShadow: [
            BoxShadow(
              color: colorScheme.shadow.withValues(alpha: 0.05),
              blurRadius: spacing.lg,
              offset: Offset(0, spacing.sm),
            ),
          ],
        ),
        child: Column(
          children: [
            CircleAvatar(
              radius: iconSize.large,
              backgroundColor: colorScheme.primary.withValues(alpha: 0.10),
              child: Icon(
                Icons.storefront,
                color: AppColors.darkPrimary,
                size: iconSize.large,
              ),
            ),

            SizedBox(height: spacing.md),

            Text(
              request.s,
              textAlign: TextAlign.center,
              style: AppTextStyles.medium(
                context,
              ).copyWith(fontWeight: FontWeight.w700),
            ),

            SizedBox(height: spacing.lg),

            if (optionalFee > 0) ...[
              _SupportNgodaNfcTile(
                value: contributionSelected,
                contributionAmount: NumberFormatService.formatAmount(
                  optionalFee,
                  currency: request.c,
                ),
                enabled: !isProcessing,
                onChanged: (value) {
                  _changePaymentFeeContribution(request, value);
                },
              ),

              SizedBox(height: spacing.md),
            ],

            PaymentCalculationCard(
              children: [
                AppValueRow(
                  label: 'Amount',
                  value: NumberFormatService.formatAmount(
                    amount,
                    currency: request.c,
                  ),
                  addBottomSpacing: false,
                ),

                if (contributionSelected) ...[
                  SizedBox(height: spacing.sm),

                  AppValueRow(
                    label: 'Support contribution',
                    value: NumberFormatService.formatAmount(
                      appliedFee,
                      currency: request.c,
                    ),
                    addBottomSpacing: false,
                  ),
                ],

                Padding(
                  padding: EdgeInsets.symmetric(vertical: spacing.sm),
                  child: const Divider(),
                ),

                AppValueRow(
                  label: 'Total',
                  value: NumberFormatService.formatAmount(
                    total,
                    currency: request.c,
                  ),
                  valueStyle: AppTextStyles.smallNumber(
                    context,
                  ).copyWith(fontWeight: FontWeight.w700),
                  addBottomSpacing: false,
                ),
              ],
            ),

            SizedBox(height: spacing.lg),

            Row(
              children: [
                Expanded(
                  child: AppButton(
                    text: 'Cancel',
                    isPrimary: false,
                    isDisabled: isProcessing,
                    onPressed: _cancelPayment,
                  ),
                ),

                SizedBox(width: spacing.md),

                Expanded(
                  child: AppButton(
                    text: 'Pay',
                    isProcessing: isProcessing,
                    onPressed: isProcessing
                        ? null
                        : () => _approvePayment(request),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLoadingState() {
    final colorScheme = context.colorScheme;

    return Center(
      key: const ValueKey('processing'),
      child: CircularProgressIndicator(color: colorScheme.primary),
    );
  }

  Widget _buildSuccessState() {
    final spacing = context.spacing;
    final iconSize = context.iconSize;

    return Center(
      key: const ValueKey('success'),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.check_circle, color: AppColors.success, size: iconSize.xl),

          SizedBox(height: spacing.md),

          Text(
            'Payment Successful',
            style: AppTextStyles.medium(
              context,
            ).copyWith(fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }

  Widget _buildFailedState() {
    final spacing = context.spacing;
    final iconSize = context.iconSize;
    final colorScheme = context.colorScheme;

    return Center(
      key: const ValueKey('failed'),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.error_outline,
            color: colorScheme.error,
            size: iconSize.xl,
          ),

          SizedBox(height: spacing.md),

          Text(
            'Payment Failed',
            style: AppTextStyles.medium(
              context,
            ).copyWith(fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }

  Future<void> _evaluatePayment(TransactionData payment) async {
    if (!mounted ||
        _isClosing ||
        isProcessing ||
        _autoApprovalStarted ||
        _isEvaluatingPayment) {
      return;
    }

    _isEvaluatingPayment = true;

    try {
      if (!_isSamePayment(_paymentData, payment)) {
        return;
      }

      final limitResponse = await ref
          .read(maxTapPaymentAmountProvider.future)
          .timeout(
            const Duration(seconds: 10),
            onTimeout: () {
              throw TimeoutException('Unable to load tap payment limit.');
            },
          );

      if (!mounted || _isClosing || !_isSamePayment(_paymentData, payment)) {
        return;
      }

      if (limitResponse.error != null) {
        throw Exception(limitResponse.error.toString());
      }

      final currencyConfig = limitResponse.result?.getByCurrency(payment.c);

      if (currencyConfig == null) {
        throw Exception(
          'No tap payment limit configured for '
          '${payment.c.toUpperCase()}.',
        );
      }

      final currencyLimit = currencyConfig.maxAmount;

      if (currencyLimit <= 0) {
        throw Exception(
          'Invalid tap payment limit for '
          '${payment.c.toUpperCase()}.',
        );
      }

      final amount = payment.a / 100;

      /*
       * Same rule as QR payment:
       *
       * amount <= maximum:
       *   automatic approval
       *
       * amount > maximum:
       *   manual review and confirmation
       */
      if (amount > currencyLimit) {
        if (!mounted || _isClosing) {
          return;
        }

        /*
         * Manual payments may optionally
         * contribute to Ngoda.
         *
         * The payment itself still starts
         * with contribution disabled.
         */
        _setPaymentFeeContribution(payment, false);

        setState(() {
          paymentState = TapPaymentState.detected;
        });

        return;
      }

      /*
       * Automatic NFC payments never include
       * the optional contribution.
       */
      await _runAutomaticApproval(payment);
    } on TimeoutException {
      await _failPayment('Unable to load tap payment limit.');
    } catch (error) {
      await _failPayment(error.toString());
    } finally {
      _isEvaluatingPayment = false;
    }
  }

  Future<void> _runAutomaticApproval(TransactionData payment) async {
    if (!mounted || _isClosing || isProcessing || _autoApprovalStarted) {
      return;
    }

    _autoApprovalStarted = true;

    try {
      if (!_isSamePayment(_paymentData, payment)) {
        return;
      }

      final auth = ref.read(authProvider);

      if (auth.isLocked) {
        await ref.read(authProvider.notifier).unlock();

        if (!mounted || _isClosing) {
          return;
        }

        if (ref.read(authProvider).isLocked) {
          await _closeScreen();
          return;
        }
      }

      if (!mounted || _isClosing || !_isSamePayment(_paymentData, payment)) {
        return;
      }

      _setPaymentFeeContribution(payment, false);

      await _approvePayment(payment);
    } catch (error) {
      await _failPayment(error.toString());
    } finally {
      _autoApprovalStarted = false;
    }
  }

  Future<void> _approvePayment(TransactionData request) async {
    if (!mounted ||
        _isClosing ||
        isProcessing ||
        !_isSamePayment(_paymentData, request)) {
      return;
    }

    setState(() {
      isProcessing = true;
      paymentState = TapPaymentState.processing;
    });

    try {
      final notifier = ref.read(walletTransactionProvider.notifier);

      await notifier.merchantPayment(transaction: request);

      final transactionState = ref.read(walletTransactionProvider);

      final loyaltyResult = transactionState.loyaltyResult;

      /*
       * Preserve the existing NFC refreshes.
       */
      ref.invalidate(customerDashboardProvider);

      ref.invalidate(loyaltySummaryProvider);

      if (!mounted || _isClosing) {
        return;
      }

      setState(() {
        isProcessing = false;
        paymentState = TapPaymentState.success;
      });

      /*
       * Stop the same NFC transaction from being
       * delivered again while the receipt and
       * loyalty UI are displayed.
       */
      _clearCurrentPayment();

      await _showReceipt(request);

      if (!mounted || _isClosing) {
        return;
      }

      await TransactionLoyaltyCelebrationService.show(context, loyaltyResult);

      notifier.reset();

      if (!mounted || _isClosing) {
        return;
      }

      await _closeScreen();
    } catch (error) {
      if (!mounted || _isClosing) {
        return;
      }

      setState(() {
        isProcessing = false;
        paymentState = TapPaymentState.failed;
      });

      await DialogService.error(context, message: error.toString());

      if (!mounted || _isClosing) {
        return;
      }

      await _closeScreen();
    }
  }

  Future<void> _failPayment(String message) async {
    if (!mounted || _isClosing || isProcessing) {
      return;
    }

    setState(() {
      paymentState = TapPaymentState.failed;
    });

    await DialogService.error(context, message: message);

    if (!mounted || _isClosing) {
      return;
    }

    await _closeScreen();
  }

  Future<void> _showReceipt(TransactionData request) async {
    if (!mounted || _isClosing) {
      return;
    }

    final transactionState = ref.read(walletTransactionProvider);

    final amount = request.a / 100;

    final contributionSelected = transactionState.paymentFeeContribution;

    final appliedFee = contributionSelected ? request.f / 100 : 0.0;

    final total = amount + appliedFee;

    final screenRoute = ModalRoute.of(context);

    await DialogService.paymentReceipt(
      context,
      title: 'Payment Successful',
      rows: [
        PaymentRow(
          'Amount',
          NumberFormatService.formatAmount(amount, currency: request.c),
          type: PaymentRowType.amount,
        ),

        if (contributionSelected)
          PaymentRow(
            'Ngoda Ecosystem Support',
            NumberFormatService.formatAmount(appliedFee, currency: request.c),
            type: PaymentRowType.amount,
          ),

        PaymentRow(
          'Total',
          NumberFormatService.formatAmount(total, currency: request.c),
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
    if (isProcessing || _isClosing) {
      return;
    }

    unawaited(_closeScreen());
  }

  void _clearCurrentPayment() {
    ref.read(tapPaymentProvider.notifier).clear();
  }

  Future<void> _closeScreen() async {
    if (_isClosing) {
      return;
    }

    _isClosing = true;

    _paymentSubscription?.close();
    _paymentSubscription = null;

    _clearCurrentPayment();

    if (!mounted) {
      return;
    }

    ref.read(walletTransactionProvider.notifier).reset();

    if (context.canPop()) {
      context.pop();
    }
  }
}

class _SupportNgodaNfcTile extends StatelessWidget {
  final bool value;
  final String contributionAmount;
  final bool enabled;
  final ValueChanged<bool> onChanged;

  const _SupportNgodaNfcTile({
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
