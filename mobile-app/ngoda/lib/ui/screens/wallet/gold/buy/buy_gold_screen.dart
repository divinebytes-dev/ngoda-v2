import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:ngoda/data_models/payment/payment_row.dart';
import 'package:ngoda/services/dialog_service.dart';
import 'package:ngoda/services/number_format_service.dart';
import 'package:ngoda/services/transaction_loyalty_celebration_service.dart';
import 'package:ngoda/ui/enums/enums.dart';
import 'package:ngoda/ui/extensions/app_size.dart';
import 'package:ngoda/ui/extensions/theme_extension.dart';
import 'package:ngoda/ui/functions/refresh_user_dashboard.dart';
import 'package:ngoda/ui/screens/finance/providers/transactions_config_provider.dart';
import 'package:ngoda/ui/screens/wallet/gold/provider/gold_price_provider.dart';
import 'package:ngoda/ui/screens/wallet/gold/provider/gold_transaction_provider.dart';
import 'package:ngoda/ui/screens/wallet/transactions/provider/customer_transaction_setup_provider.dart';
import 'package:ngoda/ui/shared/app_colors.dart';
import 'package:ngoda/ui/shared/app_text_styles.dart';
import 'package:ngoda/ui/widgets/app_button.dart';
import 'package:ngoda/ui/widgets/app_empty_state.dart';
import 'package:ngoda/ui/widgets/app_error_state.dart';
import 'package:ngoda/ui/widgets/app_loader.dart';
import 'package:ngoda/ui/widgets/app_value_row.dart';
import 'package:ngoda/ui/widgets/input_field.dart';
import 'package:ngoda/ui/widgets/payment_calculation_card.dart';
import 'package:ngoda/ui/widgets/screen_header.dart';

class BuyGoldScreen extends ConsumerStatefulWidget {
  const BuyGoldScreen({super.key});

  @override
  ConsumerState<BuyGoldScreen> createState() => _BuyGoldScreenState();
}

class _BuyGoldScreenState extends ConsumerState<BuyGoldScreen> {
  @override
  void initState() {
    super.initState();

    Future.microtask(() {
      if (!mounted) {
        return;
      }

      ref.read(goldTransactionProvider.notifier).initBuy();
    });
  }

  @override
  Widget build(BuildContext context) {
    final priceAsync = ref.watch(goldPriceProvider);

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            const ScreenHeader(
              title: 'Purchase Gold',
              subtitle: 'Buy and store gold tokens securely',
            ),
            Expanded(
              child: priceAsync.when(
                loading: () => const AppLoader(
                  message: 'Fetching gold price',
                  fullScreen: false,
                ),
                error: (error, _) =>
                    AppErrorState(title: 'Error', message: error.toString()),
                data: (response) {
                  if (response.error != null) {
                    return AppErrorState(
                      title: 'Error',
                      message: response.error!,
                      onAction: () {
                        if (context.canPop()) {
                          context.pop();
                        }
                      },
                    );
                  }

                  final price = response.result;

                  if (price == null || !price.isFinite || price <= 0) {
                    return const AppEmptyState(message: 'No Price');
                  }

                  return BuyGold(price: price);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class BuyGold extends ConsumerStatefulWidget {
  final double price;

  const BuyGold({super.key, required this.price});

  @override
  ConsumerState<BuyGold> createState() => _BuyGoldState();
}

class _BuyGoldState extends ConsumerState<BuyGold>
    with TickerProviderStateMixin {
  late final TabController _tabController;

  late final TextEditingController _amountController;

  static const _currencies = ['usd', 'gold'];

  @override
  void initState() {
    super.initState();

    _amountController = TextEditingController();

    _tabController = TabController(length: _currencies.length, vsync: this);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }

      _applyGoldPrice();
    });
  }

  @override
  void dispose() {
    _amountController.dispose();
    _tabController.dispose();

    super.dispose();
  }

  void _applyGoldPrice() {
    double spreadRate = 0;

    final config = ref.read(transactionsConfigProvider).value;

    if (config != null) {
      final spreadConfig = config.result?.get('gold_spread_buy', 'gold');

      spreadRate = spreadConfig?.percentage ?? 0;
    }

    ref
        .read(goldTransactionProvider.notifier)
        .setPrice(widget.price, spreadRate);
  }

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    final radius = context.radius;

    /*
     * This is already the normalized
     * transaction snapshot.
     *
     * It is not the customer dashboard
     * response and has no result/error
     * layer of its own.
     */
    final setupAsync = ref.watch(customerTransactionSetupProvider);

    final state = ref.watch(goldTransactionProvider);

    final notifier = ref.read(goldTransactionProvider.notifier);

    return setupAsync.when(
      loading: () => const AppLoader(
        message: 'Loading transaction details',
        fullScreen: false,
      ),
      error: (error, _) =>
          AppErrorState(title: 'Unable to buy gold', message: error.toString()),
      data: (setup) {
        final balance = setup.balances['usd'] ?? 0.0;

        final spread = state.spreadRate / 100;

        final effectivePrice = state.goldPrice * (1 + spread);
        final colorScheme = context.colorScheme;
        return Column(
          children: [
            Container(
              margin: EdgeInsets.symmetric(horizontal: spacing.md),
              padding: EdgeInsets.all(spacing.xs),
              decoration: BoxDecoration(
                color: context.theme.cardColor.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(radius.sm),
                border: Border.all(
                  color: colorScheme.outlineVariant.withValues(alpha: 0.09),
                ),
              ),
              child: TabBar(
                controller: _tabController,
                dividerColor: Colors.transparent,
                indicator: BoxDecoration(
                  color: AppColors.darkPrimary,
                  borderRadius: BorderRadius.circular(radius.sm),
                ),
                indicatorSize: TabBarIndicatorSize.tab,
                labelColor: Colors.black,
                unselectedLabelColor: context.colorScheme.onSurfaceVariant,
                labelStyle: AppTextStyles.small(
                  context,
                ).copyWith(fontWeight: FontWeight.w700),
                onTap: (index) {
                  _changeInputMode(
                    index: index,
                    balance: balance,
                    effectivePrice: effectivePrice,
                  );
                },
                tabs: const [
                  Tab(text: 'Pay USD'),
                  Tab(text: 'Enter GOLD'),
                ],
              ),
            ),
            SizedBox(height: spacing.xs),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: _currencies.map((currency) {
                  if (!widget.price.isFinite || widget.price <= 0) {
                    return const AppEmptyState(message: 'No Price');
                  }

                  return GestureDetector(
                    onTap: () {
                      FocusScope.of(context).unfocus();
                    },
                    child: Padding(
                      padding: EdgeInsets.all(spacing.md),
                      child: SingleChildScrollView(
                        child: Column(
                          children: [
                            SizedBox(height: spacing.xl),
                            Container(
                              padding: EdgeInsets.all(spacing.md),
                              decoration: BoxDecoration(
                                color: context.theme.cardColor,
                                borderRadius: BorderRadius.circular(radius.md),
                                border: Border.all(
                                  color: colorScheme.outlineVariant.withValues(
                                    alpha: 0.09,
                                  ),
                                ),
                              ),
                              child: Column(
                                children: [
                                  InputField(
                                    controller: _amountController,
                                    placeholder: _tabController.index == 0
                                        ? 'Amount (USD)'
                                        : 'Quantity (GOLD)',
                                    keyboardType:
                                        const TextInputType.numberWithOptions(
                                          decimal: true,
                                        ),
                                    onChanged: (value) {
                                      _updateAmount(
                                        value: value,
                                        currency: currency,
                                        balance: balance,
                                      );
                                    },
                                  ),
                                  SizedBox(height: spacing.sm),
                                  Container(
                                    padding: EdgeInsets.all(spacing.xs),
                                    decoration: BoxDecoration(
                                      color: context.theme.cardColor.withValues(
                                        alpha: 0.25,
                                      ),
                                      borderRadius: BorderRadius.circular(
                                        radius.cardRadius,
                                      ),
                                    ),
                                    child: Container(
                                      padding: EdgeInsets.all(spacing.md),
                                      decoration: BoxDecoration(
                                        color: context.theme.cardColor,
                                        borderRadius: BorderRadius.circular(
                                          radius.md,
                                        ),
                                        border: Border.all(
                                          color: colorScheme.outlineVariant
                                              .withValues(alpha: 0.09),
                                        ),
                                      ),
                                      child: Column(
                                        children: [
                                          AppValueRow(
                                            label: 'Available Balance',
                                            value:
                                                NumberFormatService.formatUsd(
                                                  balance,
                                                ),
                                            valueStyle:
                                                AppTextStyles.mediumNumber(
                                                  context,
                                                ),
                                          ),
                                          AppValueRow(
                                            label: 'Gold Price',
                                            value:
                                                NumberFormatService.formatUsd(
                                                  effectivePrice,
                                                ),
                                            addBottomSpacing: false,
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                  SizedBox(height: spacing.lg),
                                  if (state.result != null) _buildCalculation(),
                                  SizedBox(height: spacing.lg),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: AppButton(
                                          text: 'Cancel',
                                          isPrimary: false,
                                          isDisabled: state.isLoading,
                                          onPressed: () {
                                            _amountController.clear();

                                            notifier.reset();

                                            context.pop();
                                          },
                                        ),
                                      ),
                                      SizedBox(width: spacing.sm),
                                      Expanded(
                                        child: AppButton(
                                          text: 'Buy Gold',
                                          isProcessing: state.isLoading,
                                          onPressed:
                                              !state.isValid ||
                                                  state.isLoading ||
                                                  state.result == null
                                              ? null
                                              : handleGoldBuy,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          ],
        );
      },
    );
  }

  void _updateAmount({
    required String value,
    required String currency,
    required double balance,
  }) {
    final config = ref.read(transactionsConfigProvider).value;

    if (config == null) {
      return;
    }

    final feeConfig = config.result?.get('gold_token_buy', currency);

    if (feeConfig == null) {
      return;
    }

    ref
        .read(goldTransactionProvider.notifier)
        .updateAmount(
          value,
          balance: balance,
          feeConfig: feeConfig,
          currency: currency,
        );
  }

  void _changeInputMode({
    required int index,
    required double balance,
    required double effectivePrice,
  }) {
    final notifier = ref.read(goldTransactionProvider.notifier);

    final current =
        double.tryParse(_amountController.text.replaceAll(',', '')) ?? 0;

    final mode = index == 0 ? InputMode.fiat : InputMode.gold;

    notifier.toggleInputMode(mode);

    if (current <= 0 || effectivePrice <= 0 || !effectivePrice.isFinite) {
      return;
    }

    final converted = index == 0
        ? current * effectivePrice
        : current / effectivePrice;

    final value = index == 0
        ? converted.toStringAsFixed(2)
        : converted.toStringAsFixed(6);

    _amountController.value = TextEditingValue(
      text: value,
      selection: TextSelection.collapsed(offset: value.length),
    );

    _updateAmount(
      value: value,
      currency: index == 0 ? 'usd' : 'gold',
      balance: balance,
    );
  }

  Widget _buildCalculation() {
    final state = ref.watch(goldTransactionProvider);

    final result = state.result;

    if (result == null) {
      return const SizedBox.shrink();
    }

    return PaymentCalculationCard(
      error: state.error,
      children: [
        AppValueRow(
          label: 'You Receive',
          value: NumberFormatService.formatNumber(
            result.principal,
            decimals: 6,
          ),
          addBottomSpacing: false,
        ),

        SizedBox(height: context.spacing.sm),

        AppValueRow(
          label: 'Fee (${NumberFormatService.formatUsd(result.fiatFee)})',
          value: NumberFormatService.formatNumber(result.feeGold, decimals: 6),
          addBottomSpacing: false,
        ),

        SizedBox(height: context.spacing.sm),

        AppValueRow(
          label: 'Total Bought',
          value: NumberFormatService.formatNumber(result.quantity, decimals: 6),
          addBottomSpacing: false,
        ),

        Padding(
          padding: EdgeInsets.symmetric(vertical: context.spacing.sm),
          child: const Divider(),
        ),

        AppValueRow(
          label: 'Total Paid',
          value: NumberFormatService.formatUsd(result.fiatPaid),
          valueStyle: AppTextStyles.smallNumber(
            context,
          ).copyWith(fontWeight: FontWeight.w700),
          addBottomSpacing: false,
        ),

        SizedBox(height: context.spacing.sm),

        AppValueRow(
          label: 'New Balance',
          value: NumberFormatService.formatUsd(state.remaining),
          valueStyle: AppTextStyles.smallNumber(
            context,
          ).copyWith(fontWeight: FontWeight.w700),
          valueColor: state.remaining < 0 ? AppColors.error : AppColors.success,
          addBottomSpacing: false,
        ),
      ],
    );
  }

  Future<void> handleGoldBuy() async {
    try {
      final confirmed = await confirmBuy();

      if (confirmed != true) {
        return;
      }

      final notifier = ref.read(goldTransactionProvider.notifier);

      await notifier.goldBuy();

      final loyaltyResult = ref.read(goldTransactionProvider).loyaltyResult;

      refreshUserDashboard(ref);

      if (!mounted) {
        return;
      }

      await showReceipt();

      if (!mounted) {
        return;
      }

      if (context.canPop()) {
        context.pop();
      }

      if (!mounted) {
        return;
      }

      await TransactionLoyaltyCelebrationService.show(context, loyaltyResult);

      _amountController.clear();
      notifier.reset();
    } catch (error) {
      if (!mounted) {
        return;
      }

      await DialogService.error(context, message: error.toString());
    }
  }

  Future<bool?> confirmBuy() {
    final state = ref.read(goldTransactionProvider);

    final result = state.result;

    if (result == null) {
      return Future.value(false);
    }

    return DialogService.paymentConfirmation(
      context,
      title: 'Confirm Gold Buy',
      rows: [
        PaymentRow(
          'You will Receive',
          NumberFormatService.formatNumber(result.principal, decimals: 6),
        ),
        PaymentRow(
          'Fee (${NumberFormatService.formatUsd(result.fiatFee)})',
          NumberFormatService.formatNumber(result.feeGold, decimals: 6),
        ),
        PaymentRow(
          'Total Bought',
          NumberFormatService.formatNumber(result.quantity, decimals: 6),
        ),
        PaymentRow(
          'Total Paid',
          NumberFormatService.formatUsd(result.fiatPaid),
          isBold: true,
        ),
      ],
    );
  }

  Future<void> showReceipt() async {
    final state = ref.read(goldTransactionProvider);

    final result = state.result;

    if (result == null) {
      return;
    }

    final receiptClosed = Completer<void>();

    await DialogService.paymentReceipt(
      context,
      title: 'Gold Buy Successful',
      rows: [
        PaymentRow(
          'Received',
          NumberFormatService.formatNumber(result.principal, decimals: 6),
          type: PaymentRowType.amount,
        ),
        PaymentRow(
          'Fee',
          NumberFormatService.formatNumber(result.feeGold, decimals: 6),
          type: PaymentRowType.amount,
        ),
        PaymentRow(
          'Total Bought',
          NumberFormatService.formatNumber(result.quantity, decimals: 6),
        ),
        PaymentRow(
          'Total Paid',
          NumberFormatService.formatUsd(result.fiatPaid),
          isBold: true,
        ),
      ],
      onDone: () {
        if (!receiptClosed.isCompleted) {
          receiptClosed.complete();
        }
      },
    );

    await receiptClosed.future;
    await WidgetsBinding.instance.endOfFrame;
  }
}
