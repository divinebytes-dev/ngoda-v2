import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:ngoda/data_models/payment/payment_row.dart';
import 'package:ngoda/services/dialog_service.dart';
import 'package:ngoda/services/number_format_service.dart';
import 'package:ngoda/ui/extensions/app_size.dart';
import 'package:ngoda/ui/extensions/theme_extension.dart';
import 'package:ngoda/ui/screens/wallet/loan/provider/loan_transaction_provider.dart';
import 'package:ngoda/ui/screens/wallet/loan/state/loan_transaction_state.dart';
import 'package:ngoda/ui/screens/customer/provider/customer_dashboard_provider.dart';
import 'package:ngoda/ui/shared/app_text_styles.dart';
import 'package:ngoda/ui/widgets/app_button.dart';
import 'package:ngoda/ui/widgets/app_error_state.dart';
import 'package:ngoda/ui/widgets/app_loader.dart';
import 'package:ngoda/ui/widgets/app_value_row.dart';
import 'package:ngoda/ui/widgets/input_field.dart';
import 'package:ngoda/ui/widgets/payment_calculation_card.dart';
import 'package:ngoda/ui/widgets/view_header.dart';

class TopupCollateralScreen extends ConsumerStatefulWidget {
  const TopupCollateralScreen({super.key});

  @override
  ConsumerState<TopupCollateralScreen> createState() =>
      _TopupCollateralScreenState();
}

class _TopupCollateralScreenState extends ConsumerState<TopupCollateralScreen> {
  final TextEditingController amountController = TextEditingController();

  bool _initialized = false;

  @override
  void dispose() {
    amountController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;

    final dashboardAsync = ref.watch(customerDashboardProvider);

    final state = ref.watch(loanTransactionProvider);

    return Scaffold(
      body: SafeArea(
        child: GestureDetector(
          onTap: () => FocusScope.of(context).unfocus(),
          child: Padding(
            padding: EdgeInsets.all(spacing.lg),
            child: dashboardAsync.when(
              loading: () => const AppLoader(),
              error: (error, _) => AppErrorState(message: error.toString()),
              data: (dashboardResult) {
                final dashboard = dashboardResult.result;

                if (dashboard == null) {
                  return AppErrorState(
                    message:
                        dashboardResult.error ??
                        'Unable to load collateral information.',
                  );
                }

                final loanSummary = dashboard.loanSummary;

                final requiredCollateral = loanSummary.requiredCollateral;

                final availableBalance = loanSummary.gold.available.grams;

                _initializeTransaction(availableBalance: availableBalance);

                return SingleChildScrollView(
                  child: Column(
                    children: [
                      ViewHeader(
                        title: 'Topup Loan Collateral',
                        subtitle: 'Collateral will be shared by all risk loans',
                        onClose: _close,
                      ),

                      SizedBox(height: spacing.lg),

                      Container(
                        width: double.infinity,
                        padding: EdgeInsets.all(spacing.lg),
                        decoration: BoxDecoration(
                          color: context.theme.cardColor,
                          borderRadius: BorderRadius.circular(
                            context.radius.lg,
                          ),
                        ),
                        child: Column(
                          children: [
                            InputField(
                              controller: amountController,
                              placeholder: 'Collateral',
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),
                              onChanged: (value) {
                                _updateAmount(
                                  value,
                                  requiredCollateral: requiredCollateral,
                                  availableBalance: availableBalance,
                                );
                              },
                              suffixIcon: Padding(
                                padding: EdgeInsets.symmetric(
                                  horizontal: spacing.md,
                                ),
                                child: GestureDetector(
                                  onTap: () {
                                    _setMaximum(
                                      requiredCollateral: requiredCollateral,
                                      availableBalance: availableBalance,
                                    );
                                  },
                                  child: Align(
                                    alignment: Alignment.center,
                                    widthFactor: 1,
                                    child: Text(
                                      'Max',
                                      style: AppTextStyles.small(context)
                                          .copyWith(
                                            color: Theme.of(
                                              context,
                                            ).colorScheme.primary,
                                            fontWeight: FontWeight.w700,
                                          ),
                                    ),
                                  ),
                                ),
                              ),
                            ),

                            SizedBox(height: spacing.md),

                            _buildAvailableBalance(context, availableBalance),

                            if (state.amount > 0) ...[
                              SizedBox(height: spacing.lg),
                              _buildCalculation(context, state),
                            ],

                            if (state.error != null) ...[
                              SizedBox(height: spacing.md),
                              Align(
                                alignment: Alignment.centerLeft,
                                child: Text(
                                  state.error!,
                                  style: AppTextStyles.small(context).copyWith(
                                    color: Theme.of(context).colorScheme.error,
                                  ),
                                ),
                              ),
                            ],

                            SizedBox(height: spacing.lg),

                            Row(
                              children: [
                                Expanded(
                                  child: AppButton(
                                    text: 'Cancel',
                                    isPrimary: false,
                                    isDisabled: state.isLoading,
                                    onPressed: _close,
                                  ),
                                ),

                                SizedBox(width: spacing.md),

                                Expanded(
                                  child: AppButton(
                                    text: 'Top up',
                                    isProcessing: state.isLoading,
                                    onPressed: !state.isValid || state.isLoading
                                        ? null
                                        : _handleTopUp,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  void _initializeTransaction({required double availableBalance}) {
    if (_initialized) {
      return;
    }

    _initialized = true;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }

      final notifier = ref.read(loanTransactionProvider.notifier);

      /*
       * Start a fresh collateral
       * transaction and store the
       * customer's available gold.
       */
      notifier.reset();

      notifier.init(principalBalance: availableBalance, interestBalance: 0);
    });
  }

  void _updateAmount(
    String value, {
    required double requiredCollateral,
    required double availableBalance,
  }) {
    final notifier = ref.read(loanTransactionProvider.notifier);

    var amount = NumberFormatService.anyToDouble(value.trim());

    final maximum = _getMaxCollateral(
      requiredCollateral: requiredCollateral,
      availableBalance: availableBalance,
    );

    if (amount > maximum) {
      amount = maximum;

      amountController.text = amount.toStringAsFixed(2);

      amountController.selection = TextSelection.fromPosition(
        TextPosition(offset: amountController.text.length),
      );
    }

    notifier.updateCollateralAmount(amount, balance: requiredCollateral);
  }

  void _setMaximum({
    required double requiredCollateral,
    required double availableBalance,
  }) {
    final maximum = _getMaxCollateral(
      requiredCollateral: requiredCollateral,
      availableBalance: availableBalance,
    );

    amountController.text = maximum.toStringAsFixed(2);

    amountController.selection = TextSelection.fromPosition(
      TextPosition(offset: amountController.text.length),
    );

    ref
        .read(loanTransactionProvider.notifier)
        .updateCollateralAmount(maximum, balance: requiredCollateral);
  }

  double _getMaxCollateral({
    required double requiredCollateral,
    required double availableBalance,
  }) {
    if (requiredCollateral <= 0 || availableBalance <= 0) {
      return 0;
    }

    /*
     * Collateral entry is 2dp.
     *
     * Round the required amount upward
     * where the customer's available
     * gold can cover the rounded value.
     */
    final roundedUp = (requiredCollateral * 100).ceilToDouble() / 100;

    if (roundedUp <= availableBalance) {
      return roundedUp;
    }

    /*
     * If rounding upward would exceed
     * available gold, use the 2dp value
     * that does not exceed it.
     */
    final roundedDown = (requiredCollateral * 100).floorToDouble() / 100;

    if (roundedDown <= availableBalance) {
      return roundedDown;
    }

    /*
     * The customer cannot cover the
     * required collateral amount.
     */
    return 0;
  }

  Widget _buildAvailableBalance(BuildContext context, double balance) {
    final spacing = context.spacing;

    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(spacing.md),
      decoration: BoxDecoration(
        color: context.theme.cardColor.withValues(alpha: 0.25),
        borderRadius: BorderRadius.circular(context.radius.md),
      ),
      child: AppValueRow(
        label: 'Available Balance',
        value: '${NumberFormatService.formatNumber(balance, decimals: 6)} g',
        valueStyle: AppTextStyles.mediumNumber(context),
        addBottomSpacing: false,
      ),
    );
  }

  Widget _buildCalculation(BuildContext context, LoanTransactionState state) {
    final spacing = context.spacing;
    final colorScheme = Theme.of(context).colorScheme;

    return PaymentCalculationCard(
      children: [
        AppValueRow(
          label: 'Collateral',
          value:
              '${NumberFormatService.formatNumber(state.amount, decimals: 2)} g',
        ),

        Divider(height: spacing.lg),

        AppValueRow(
          label: 'Available Gold After Top Up',
          value:
              '${NumberFormatService.formatNumber(state.remainingBalance, decimals: 6)} g',
          valueStyle: AppTextStyles.mediumNumber(context),
          valueColor: state.remainingBalance < 0
              ? colorScheme.error
              : Colors.green,
          addBottomSpacing: false,
        ),
      ],
    );
  }

  Future<void> _handleTopUp() async {
    final notifier = ref.read(loanTransactionProvider.notifier);

    try {
      final confirmed = await _confirmTopUp();

      if (confirmed != true) {
        return;
      }

      await notifier.topupCollateral();

      if (!mounted) {
        return;
      }

      await DialogService.success(
        context,
        message: 'Collateral Top Up Successful',
      );

      if (!mounted) {
        return;
      }

      /*
       * topupCollateral() already
       * invalidates the customer
       * dashboard after success.
       */
      notifier.reset();
      amountController.clear();

      context.pop();
    } catch (error) {
      if (!mounted) {
        return;
      }

      await DialogService.error(context, message: error.toString());
    }
  }

  Future<bool?> _confirmTopUp() {
    final state = ref.read(loanTransactionProvider);

    return DialogService.paymentConfirmation(
      context,
      title: 'Confirm Collateral Top Up',
      rows: [
        PaymentRow(
          'Total Collateral',
          '${NumberFormatService.formatNumber(state.amount, decimals: 2)} g',
          isBold: true,
        ),
      ],
    );
  }

  void _close() {
    amountController.clear();

    ref.read(loanTransactionProvider.notifier).reset();

    context.pop();
  }
}
