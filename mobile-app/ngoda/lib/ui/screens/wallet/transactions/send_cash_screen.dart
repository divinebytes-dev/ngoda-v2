import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:ngoda/data_models/payment/payment_row.dart';
import 'package:ngoda/services/currency_service.dart';
import 'package:ngoda/services/dialog_service.dart';
import 'package:ngoda/services/number_format_service.dart';
import 'package:ngoda/services/transaction_loyalty_celebration_service.dart';
import 'package:ngoda/ui/enums/enums.dart';
import 'package:ngoda/ui/extensions/app_size.dart';
import 'package:ngoda/ui/extensions/theme_extension.dart';
import 'package:ngoda/ui/functions/refresh_user_dashboard.dart';
import 'package:ngoda/ui/screens/finance/providers/transactions_config_provider.dart';
import 'package:ngoda/ui/screens/gamification/provider/loyalty_summary_provider.dart';
import 'package:ngoda/ui/screens/wallet/transactions/provider/cash_tranfere_fee_points_config_provider.dart';
import 'package:ngoda/ui/screens/wallet/transactions/provider/customer_transaction_setup_provider.dart';
import 'package:ngoda/ui/screens/wallet/transactions/provider/wallet_transaction_provider.dart';
import 'package:ngoda/ui/shared/app_colors.dart';
import 'package:ngoda/ui/shared/app_text_styles.dart';
import 'package:ngoda/ui/widgets/app_button.dart';
import 'package:ngoda/ui/widgets/app_error_state.dart';
import 'package:ngoda/ui/widgets/app_loader.dart';
import 'package:ngoda/ui/widgets/app_value_row.dart';
import 'package:ngoda/ui/widgets/currency_field.dart';
import 'package:ngoda/ui/widgets/input_field.dart';
import 'package:ngoda/ui/widgets/view_header.dart';

class SendCashScreen extends ConsumerStatefulWidget {
  const SendCashScreen({super.key});

  @override
  ConsumerState<SendCashScreen> createState() => _SendCashScreenState();
}

class _SendCashScreenState extends ConsumerState<SendCashScreen> {
  final identifierCtrl = TextEditingController();
  final amountCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();

    Future.microtask(() {
      if (!mounted) return;

      ref.read(walletTransactionProvider.notifier).initReference();
    });
  }

  @override
  void dispose() {
    identifierCtrl.dispose();
    amountCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    final radius = context.radius;
    final iconSize = context.iconSize;
    final colorScheme = context.colorScheme;

    final dashboardAsync = ref.watch(customerTransactionSetupProvider);

    final transactionConfigAsync = ref.watch(transactionsConfigProvider);

    final feeConfigurationAsync = ref.watch(
      cashTransferFeeConfigurationProvider,
    );

    final loyaltyAsync = ref.watch(loyaltySummaryProvider);

    final state = ref.watch(walletTransactionProvider);

    final notifier = ref.read(walletTransactionProvider.notifier);

    /*
     * Keep transaction state synchronized with the
     * latest transfer-fee configuration.
     */
    ref.listen(cashTransferFeeConfigurationProvider, (previous, next) {
      final configuration = next.value?.result;

      if (configuration == null) {
        return;
      }

      notifier.updateCashTransferFeeConfiguration(configuration);
    });

    /*
     * Keep the points balance used by the transaction
     * calculation synchronized with loyalty state.
     */
    ref.listen(loyaltySummaryProvider, (previous, next) {
      final availablePoints = next.value?.result?.availablePoints;

      if (availablePoints == null) {
        return;
      }

      notifier.updateAvailablePoints(availablePoints);
    });

    /*
     * WidgetRef.listen does not fire for an already-cached
     * provider value in the Riverpod version used by the app.
     *
     * Synchronize those cached values after the current frame.
     * Future changes continue through the listeners above.
     */
    final loadedConfiguration = feeConfigurationAsync.value?.result;

    final loadedAvailablePoints = loyaltyAsync.value?.result?.availablePoints;

    final configurationNeedsSync =
        loadedConfiguration != null &&
        !identical(state.configuration, loadedConfiguration);

    final pointsNeedSync =
        loadedAvailablePoints != null &&
        state.availablePoints != loadedAvailablePoints;

    if (configurationNeedsSync || pointsNeedSync) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) {
          return;
        }

        if (configurationNeedsSync) {
          notifier.updateCashTransferFeeConfiguration(loadedConfiguration);
        }

        if (pointsNeedSync) {
          notifier.updateAvailablePoints(loadedAvailablePoints);
        }
      });
    }

    if (dashboardAsync.isLoading ||
        transactionConfigAsync.isLoading ||
        feeConfigurationAsync.isLoading ||
        loyaltyAsync.isLoading) {
      return const Scaffold(
        body: AppLoader(message: 'Preparing cash transfer'),
      );
    }

    final asynchronousError = dashboardAsync.hasError
        ? dashboardAsync.error
        : transactionConfigAsync.hasError
        ? transactionConfigAsync.error
        : feeConfigurationAsync.hasError
        ? feeConfigurationAsync.error
        : loyaltyAsync.hasError
        ? loyaltyAsync.error
        : null;

    if (asynchronousError != null) {
      return Scaffold(
        body: SafeArea(
          child: AppErrorState(message: asynchronousError.toString()),
        ),
      );
    }

    final responseError =
        transactionConfigAsync.value?.error ??
        feeConfigurationAsync.value?.error ??
        loyaltyAsync.value?.error;

    if (responseError != null) {
      return Scaffold(
        body: SafeArea(child: AppErrorState(message: responseError.toString())),
      );
    }

    final dashboard = dashboardAsync.value;

    if (dashboard == null) {
      return const Scaffold(
        body: SafeArea(
          child: AppErrorState(message: 'Transfer details are not available'),
        ),
      );
    }

    if (loadedConfiguration == null || loadedAvailablePoints == null) {
      return const Scaffold(
        body: SafeArea(
          child: AppErrorState(
            message: 'Cash transfer configuration is not available',
          ),
        ),
      );
    }

    /*
     * Do not expose the form until configuration and points
     * have been copied into WalletTransactionState.
     *
     * This guarantees that the first amount entered by the
     * user is calculated against the correct configuration.
     */
    if (!identical(state.configuration, loadedConfiguration) ||
        state.availablePoints != loadedAvailablePoints) {
      return const Scaffold(
        body: AppLoader(message: 'Preparing cash transfer'),
      );
    }

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

    final balances = dashboard.balances;

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
                  title: 'Send Money',
                  subtitle: 'Transfer funds securely to another user',
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
                              InputField(
                                controller: identifierCtrl,
                                placeholder: 'Receiver email / phone',
                                keyboardType: TextInputType.text,
                                onChanged: notifier.updateIdentifier,
                              ),
                              SizedBox(height: spacing.sm),
                              CurrencyField(
                                selected: state.currency,
                                currencies: currencies,
                                balances: balances,
                                onSelect: (value) {
                                  notifier.updateCurrency(value, balances);

                                  _updateAmount(amountCtrl.text, dashboard);
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
                                  _updateAmount(value, dashboard);
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
                              if (state.currency != null) ...[
                                SizedBox(height: spacing.lg),
                                _buildCalculation(),
                                SizedBox(height: spacing.md),
                                _buildFeePaymentSelector(),
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
                                      text: 'Send',
                                      isProcessing: state.isLoading,
                                      onPressed:
                                          !state.isValid || state.isLoading
                                          ? null
                                          : handleCashSend,
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

  void _updateAmount(String value, dynamic dashboard) {
    final transactionConfig = ref.read(transactionsConfigProvider).value;

    final state = ref.read(walletTransactionProvider);

    final currency = state.currency;

    if (transactionConfig == null || currency == null) {
      return;
    }

    if (transactionConfig.error != null) {
      return;
    }

    final feeConfig = transactionConfig.result?.get(
      'cash_transfer',
      currency.code,
    );

    if (feeConfig == null) {
      return;
    }

    final balance = dashboard.balances[currency.code] ?? 0;

    ref
        .read(walletTransactionProvider.notifier)
        .updateSendAmount(value, feeConfig: feeConfig, balance: balance);
  }

  Widget _buildCalculation() {
    final state = ref.watch(walletTransactionProvider);

    final spacing = context.spacing;
    final radius = context.radius;
    final colorScheme = context.colorScheme;

    final currency = state.currency?.code ?? 'usd';

    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(spacing.md),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(radius.md),
      ),
      child: Column(
        children: [
          AppValueRow(
            label: 'Available Balance',
            value: NumberFormatService.formatAmount(
              state.balance,
              currency: currency,
            ),
          ),
          AppValueRow(
            label: 'Fee (${state.feePercent.toStringAsFixed(2)}%)',
            value: NumberFormatService.formatAmount(
              state.feeAmount,
              currency: currency,
            ),
          ),
          AppValueRow(
            label: 'Fee (Points)',
            value: NumberFormatService.formatPoints(state.feePoints),
          ),
          AppValueRow(
            label: 'Available Points',
            value: NumberFormatService.formatPoints(state.availablePoints),
          ),
          AppValueRow(
            label: 'Total Cash Debit',
            value: NumberFormatService.formatAmount(
              state.totalDebit,
              currency: currency,
            ),
            valueStyle: AppTextStyles.smallNumber(
              context,
            ).copyWith(fontWeight: FontWeight.w700),
          ),
          AppValueRow(
            label: 'New Balance',
            value: NumberFormatService.formatAmount(
              state.remaining,
              currency: currency,
            ),
            valueStyle: AppTextStyles.smallNumber(context).copyWith(
              fontWeight: FontWeight.w700,
              color: state.remaining < 0
                  ? colorScheme.error
                  : AppColors.success,
            ),
            addBottomSpacing: state.error != null,
          ),
        ],
      ),
    );
  }

  Widget _buildFeePaymentSelector() {
    final spacing = context.spacing;
    final radius = context.radius;
    final iconSize = context.iconSize;
    final colorScheme = context.colorScheme;

    final state = ref.watch(walletTransactionProvider);

    final notifier = ref.read(walletTransactionProvider.notifier);

    final pointsReady = state.feePoints > 0;

    final redemptionEnabled =
        state.configuration?.loyaltyRedemptionEnabled == true;

    final pointsShortfall = state.feePoints > state.availablePoints
        ? state.feePoints - state.availablePoints
        : 0;

    final subtitle = !redemptionEnabled
        ? 'Points payment is not available for this account'
        : !pointsReady
        ? 'Enter an amount to calculate the points fee'
        : state.canPayWithPoints
        ? '${NumberFormatService.formatPoints(state.availablePoints)} points available'
        : '${NumberFormatService.formatPoints(pointsShortfall)} more points required';

    final pointsColor = state.canPayWithPoints
        ? AppColors.success
        : colorScheme.onSurfaceVariant;

    return Material(
      color: context.theme.scaffoldBackgroundColor,
      borderRadius: BorderRadius.circular(radius.md),
      child: SwitchListTile.adaptive(
        contentPadding: EdgeInsets.symmetric(
          horizontal: spacing.md,
          vertical: spacing.xs,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radius.md),
          side: BorderSide(color: colorScheme.outlineVariant),
        ),
        value: state.feePaymentMethod.isPoints,
        onChanged: state.canPayWithPoints && !state.isLoading
            ? (usePoints) {
                notifier.updateFeePaymentMethod(
                  usePoints ? FeePaymentMethod.points : FeePaymentMethod.cash,
                );
              }
            : null,
        title: Text(
          'Pay transfer fee with points',
          style: AppTextStyles.small(
            context,
          ).copyWith(fontWeight: FontWeight.w700),
        ),
        subtitle: Text(
          subtitle,
          style: AppTextStyles.tiny(context).copyWith(color: pointsColor),
        ),
        secondary: Icon(
          Icons.stars_rounded,
          size: iconSize.large,
          color: state.canPayWithPoints
              ? AppColors.gold
              : colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }

  Future<void> handleCashSend() async {
    try {
      final confirmed = await confirmTransfer();

      if (confirmed != true) {
        return;
      }

      final notifier = ref.read(walletTransactionProvider.notifier);

      await notifier.cashTransfer();

      final loyaltyResult = ref.read(walletTransactionProvider).loyaltyResult;

      refreshUserDashboard(ref);

      if (!mounted) {
        return;
      }

      await showReceipt();

      if (!mounted) {
        return;
      }

      await TransactionLoyaltyCelebrationService.show(context, loyaltyResult);

      if (!mounted) {
        return;
      }

      _resetForm();
    } catch (error) {
      if (!mounted) {
        return;
      }

      await DialogService.error(context, message: error.toString());
    }
  }

  Future<bool?> confirmTransfer() {
    final state = ref.read(walletTransactionProvider);

    final currency = state.currency?.code ?? 'usd';

    return DialogService.paymentConfirmation(
      context,
      title: 'Confirm Cash Send',
      rows: [
        PaymentRow('To', state.identifier!, type: PaymentRowType.text),
        PaymentRow(
          'Amount',
          NumberFormatService.formatAmount(state.amount, currency: currency),
        ),
        PaymentRow(
          'Fee payment',
          state.feePaymentMethod.isPoints ? 'Points' : 'Cash',
          type: PaymentRowType.text,
        ),
        if (state.feePaymentMethod.isPoints)
          PaymentRow(
            'Fee (Points)',
            NumberFormatService.formatPoints(state.feePoints),
          )
        else
          PaymentRow(
            'Fee (${state.feePercent.toStringAsFixed(2)}%)',
            NumberFormatService.formatAmount(
              state.feeAmount,
              currency: currency,
            ),
          ),
        PaymentRow(
          'Total Cash Debit',
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

    final currency = state.currency?.code ?? 'usd';

    /*
     * Capture this screen's route before opening the
     * receipt. While the receipt is visible this route
     * is no longer current.
     */
    final screenRoute = ModalRoute.of(context);

    await DialogService.paymentReceipt(
      context,
      title: 'Transfer Successful',
      rows: [
        PaymentRow(
          'Amount',
          NumberFormatService.formatAmount(state.amount, currency: currency),
          type: PaymentRowType.amount,
        ),
        PaymentRow('To', state.identifier!, type: PaymentRowType.text),
        if (state.feePaymentMethod.isPoints)
          PaymentRow(
            'Fee (Points)',
            NumberFormatService.formatPoints(state.feePoints),
            type: PaymentRowType.amount,
          )
        else
          PaymentRow(
            'Fee',
            NumberFormatService.formatAmount(
              state.feeAmount,
              currency: currency,
            ),
            type: PaymentRowType.amount,
          ),
        PaymentRow(
          'Total Cash Debit',
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

    /*
     * Some paymentReceipt implementations return after
     * installing the dialog rather than after it closes.
     * Wait for the dialog route to be installed.
     */
    await WidgetsBinding.instance.endOfFrame;

    /*
     * Continue only after the receipt has been removed
     * and this transaction screen is current again.
     *
     * This also covers Android back and barrier dismissal.
     */
    while (mounted && screenRoute != null && !screenRoute.isCurrent) {
      await WidgetsBinding.instance.endOfFrame;
    }

    /*
     * Give the reverse dialog animation time to finish
     * before showing the loyalty celebration.
     */
    await Future<void>.delayed(const Duration(milliseconds: 200));
  }

  void _resetForm() {
    amountCtrl.clear();
    identifierCtrl.clear();

    ref.read(walletTransactionProvider.notifier).resetCashTransfer();
  }

  void _closeScreen() {
    if (!mounted) {
      return;
    }

    FocusScope.of(context).unfocus();

    _resetForm();

    if (context.canPop()) {
      context.pop();
    }
  }
}
