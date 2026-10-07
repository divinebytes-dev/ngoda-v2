import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:ngoda/data_models/payment/payment_row.dart';
import 'package:ngoda/services/dialog_service.dart';
import 'package:ngoda/services/number_format_service.dart';
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

class SellGoldScreen extends ConsumerStatefulWidget {
  const SellGoldScreen({super.key});

  @override
  ConsumerState<SellGoldScreen> createState() => _SellGoldScreenState();
}

class _SellGoldScreenState extends ConsumerState<SellGoldScreen> {
  @override
  void initState() {
    super.initState();

    Future.microtask(() {
      if (!mounted) {
        return;
      }

      ref.read(goldTransactionProvider.notifier).initSell();
    });
  }

  Future<void> _refresh() async {
    ref.invalidate(goldPriceProvider);
    ref.invalidate(transactionsConfigProvider);
    ref.invalidate(customerTransactionSetupProvider);

    await Future.wait([
      ref.read(goldPriceProvider.future),
      ref.read(transactionsConfigProvider.future),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final priceAsync = ref.watch(goldPriceProvider);

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            const ScreenHeader(
              title: 'Sell Gold',
              subtitle: 'Sell your gold tokens securely',
            ),
            Expanded(
              child: priceAsync.when(
                loading: () => const AppLoader(
                  message: 'Fetching gold price',
                  fullScreen: false,
                ),
                error: (error, _) => _RefreshableState(
                  onRefresh: _refresh,
                  child: AppErrorState(
                    title: 'Error',
                    message: error.toString(),
                    onAction: () => context.pop(),
                  ),
                ),
                data: (response) {
                  if (response.error != null) {
                    return _RefreshableState(
                      onRefresh: _refresh,
                      child: AppErrorState(
                        title: 'Error',
                        message: response.error!,
                        onAction: () => context.pop(),
                      ),
                    );
                  }

                  final price = response.result;

                  if (price == null || !price.isFinite || price <= 0) {
                    return _RefreshableState(
                      onRefresh: _refresh,
                      child: const AppEmptyState(
                        message: 'Gold price is unavailable',
                      ),
                    );
                  }

                  return SellGold(price: price, onRefresh: _refresh);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class SellGold extends ConsumerStatefulWidget {
  final double price;
  final Future<void> Function() onRefresh;

  const SellGold({super.key, required this.price, required this.onRefresh});

  @override
  ConsumerState<SellGold> createState() => _SellGoldState();
}

class _SellGoldState extends ConsumerState<SellGold>
    with TickerProviderStateMixin {
  late final TabController _tabController;

  late final TextEditingController _amountController;

  @override
  void initState() {
    super.initState();

    _amountController = TextEditingController();

    _tabController = TabController(length: 2, vsync: this);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }

      _applyPrice(widget.price);
    });
  }

  @override
  void didUpdateWidget(covariant SellGold oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.price != widget.price) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) {
          return;
        }

        _applyPrice(widget.price);
      });
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    _amountController.dispose();

    super.dispose();
  }

  void _applyPrice(double price) {
    final configResponse = ref.read(transactionsConfigProvider).value;

    final spreadConfig = configResponse?.result?.get(
      'gold_spread_sell',
      'gold',
    );

    final spread = spreadConfig?.percentage ?? 0;

    ref.read(goldTransactionProvider.notifier).setPrice(price, spread);

    final value = _amountController.text.trim();

    if (value.isNotEmpty) {
      _updateAmount(value);
    }
  }

  @override
  Widget build(BuildContext context) {
    final setupAsync = ref.watch(customerTransactionSetupProvider);

    final state = ref.watch(goldTransactionProvider);

    final notifier = ref.read(goldTransactionProvider.notifier);
    final colorScheme = context.colorScheme;

    return setupAsync.when(
      loading: () =>
          const AppLoader(message: 'Loading gold balance', fullScreen: false),
      error: (error, _) => _RefreshableState(
        onRefresh: widget.onRefresh,
        child: AppErrorState(
          title: 'Unable to load gold balance',
          message: error.toString(),
          onAction: () => context.pop(),
        ),
      ),
      data: (setup) {
        /*
         * customerTransactionSetupProvider
         * has already converted the dashboard
         * into the transaction snapshot.
         */
        final balance = setup.balances['gold'];

        if (balance == null) {
          return _RefreshableState(
            onRefresh: widget.onRefresh,
            child: const AppEmptyState(message: 'Gold balance is unavailable'),
          );
        }

        final spread = state.spreadRate / 100;

        final effectivePrice = state.goldPrice * (1 - spread);

        return Column(
          children: [
            Container(
              margin: EdgeInsets.symmetric(horizontal: context.spacing.md),
              padding: EdgeInsets.all(context.spacing.xs),
              decoration: BoxDecoration(
                color: context.theme.cardColor.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(context.radius.sm),
              ),
              child: TabBar(
                controller: _tabController,
                dividerColor: Colors.transparent,
                indicator: BoxDecoration(
                  color: AppColors.darkPrimary,
                  borderRadius: BorderRadius.circular(context.radius.sm),
                ),
                indicatorSize: TabBarIndicatorSize.tab,
                labelColor: Colors.black,
                unselectedLabelColor: context.colorScheme.onSurfaceVariant,
                labelStyle: AppTextStyles.small(
                  context,
                ).copyWith(fontWeight: FontWeight.w700),
                onTap: (index) {
                  _changeInputMode(index, effectivePrice);
                },
                tabs: const [
                  Tab(text: 'Receive USD'),
                  Tab(text: 'Enter GOLD'),
                ],
              ),
            ),

            SizedBox(height: context.spacing.xs),

            Expanded(
              child: RefreshIndicator(
                onRefresh: widget.onRefresh,
                triggerMode: RefreshIndicatorTriggerMode.anywhere,
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  padding: EdgeInsets.all(context.spacing.md),
                  children: [
                    SizedBox(height: context.spacing.xl),

                    Container(
                      padding: EdgeInsets.all(context.spacing.padding),
                      decoration: BoxDecoration(
                        color: context.theme.cardColor,
                        borderRadius: BorderRadius.circular(
                          context.radius.cardRadius,
                        ),
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
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            onChanged: _updateAmount,
                          ),

                          SizedBox(height: context.spacing.sm),

                          Container(
                            padding: EdgeInsets.all(context.spacing.sm),
                            decoration: BoxDecoration(
                              color: context.theme.cardColor.withValues(
                                alpha: 0.25,
                              ),
                              borderRadius: BorderRadius.circular(
                                context.radius.cardRadius,
                              ),
                              border: Border.all(
                                color: colorScheme.outlineVariant.withValues(
                                  alpha: 0.09,
                                ),
                              ),
                            ),
                            child: Column(
                              children: [
                                AppValueRow(
                                  label: 'Available Balance',
                                  value: NumberFormatService.formatNumber(
                                    balance,
                                    decimals: 6,
                                  ),
                                  valueStyle: AppTextStyles.mediumNumber(
                                    context,
                                  ),
                                  addBottomSpacing: false,
                                ),

                                SizedBox(height: context.spacing.sm),

                                AppValueRow(
                                  label: 'Gold Sell Price',
                                  value: NumberFormatService.formatUsd(
                                    effectivePrice,
                                  ),
                                  addBottomSpacing: false,
                                ),
                              ],
                            ),
                          ),

                          if (state.amount > 0) ...[
                            SizedBox(height: context.spacing.lg),
                            _buildCalculation(),
                          ],

                          SizedBox(height: context.spacing.lg),

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

                              SizedBox(width: context.spacing.sm),

                              Expanded(
                                child: AppButton(
                                  text: 'Sell Gold',
                                  isProcessing: state.isLoading,
                                  onPressed: !state.isValid || state.isLoading
                                      ? null
                                      : _handleSellGold,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),

                    SizedBox(height: context.spacing.xl),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  void _changeInputMode(int index, double effectivePrice) {
    final current =
        double.tryParse(_amountController.text.trim().replaceAll(',', '')) ?? 0;

    final mode = index == 0 ? InputMode.fiat : InputMode.gold;

    ref.read(goldTransactionProvider.notifier).toggleInputMode(mode);

    if (current > 0 && effectivePrice > 0 && effectivePrice.isFinite) {
      if (index == 0) {
        /*
         * Previous mode was GOLD.
         * Convert entered GOLD quantity
         * to USD proceeds.
         */
        final fiatAmount = current * effectivePrice;

        _amountController.text = fiatAmount.toStringAsFixed(2);
      } else {
        /*
         * Previous mode was USD.
         * Convert desired USD proceeds
         * to GOLD quantity.
         */
        final goldQuantity = current / effectivePrice;

        _amountController.text = goldQuantity.toStringAsFixed(6);
      }

      _amountController.selection = TextSelection.collapsed(
        offset: _amountController.text.length,
      );
    }

    setState(() {});

    if (_amountController.text.trim().isNotEmpty) {
      _updateAmount(_amountController.text);
    }
  }

  void _updateAmount(String value) {
    final setup = ref.read(customerTransactionSetupProvider).value;

    final configResponse = ref.read(transactionsConfigProvider).value;

    final balance = setup?.balances['gold'];

    if (setup == null || configResponse == null || balance == null) {
      return;
    }

    final currency = _tabController.index == 0 ? 'usd' : 'gold';

    final feeConfig = configResponse.result?.get('gold_token_sell', currency);

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

  Widget _buildCalculation() {
    final state = ref.watch(goldTransactionProvider);

    final result = state.result;

    if (result == null) {
      return const SizedBox.shrink();
    }

    return PaymentCalculationCard(
      error: state.error,
      children: [
        if (state.currency != 'gold') ...[
          AppValueRow(
            label: 'You Receive',
            value: NumberFormatService.formatUsd(result.principal),
            valueStyle: AppTextStyles.smallNumber(
              context,
            ).copyWith(fontWeight: FontWeight.w700),
            addBottomSpacing: false,
          ),

          SizedBox(height: context.spacing.sm),
        ],

        AppValueRow(
          label: 'Fee (${NumberFormatService.formatUsd(result.fiatFee)})',
          value: NumberFormatService.formatNumber(result.feeGold, decimals: 6),
          addBottomSpacing: false,
        ),

        SizedBox(height: context.spacing.sm),

        AppValueRow(
          label: 'Total Sold',
          value: NumberFormatService.formatNumber(result.quantity, decimals: 6),
          addBottomSpacing: false,
        ),

        Padding(
          padding: EdgeInsets.symmetric(vertical: context.spacing.sm),
          child: const Divider(),
        ),

        AppValueRow(
          label: 'Total Received',
          value: NumberFormatService.formatUsd(result.fiatPaid),
          valueStyle: AppTextStyles.smallNumber(
            context,
          ).copyWith(fontWeight: FontWeight.w700),
          addBottomSpacing: false,
        ),

        SizedBox(height: context.spacing.sm),

        AppValueRow(
          label: 'New Gold Balance',
          value: NumberFormatService.formatNumber(state.remaining, decimals: 6),
          valueStyle: AppTextStyles.smallNumber(
            context,
          ).copyWith(fontWeight: FontWeight.w700),
          valueColor: state.remaining < 0 ? AppColors.error : AppColors.success,
          addBottomSpacing: false,
        ),
      ],
    );
  }

  Future<void> _handleSellGold() async {
    try {
      final confirmed = await _confirmSell();

      if (confirmed != true) {
        return;
      }

      final notifier = ref.read(goldTransactionProvider.notifier);

      await notifier.goldSell();

      refreshUserDashboard(ref);

      if (!mounted) {
        return;
      }

      await _showReceipt();

      _amountController.clear();
      notifier.reset();
    } catch (error) {
      if (!mounted) {
        return;
      }

      await DialogService.error(context, message: error.toString());
    }
  }

  Future<bool?> _confirmSell() {
    final state = ref.read(goldTransactionProvider);

    final result = state.result;

    if (result == null) {
      return Future.value(false);
    }

    return DialogService.paymentConfirmation(
      context,
      title: 'Confirm Gold Sell',
      rows: [
        PaymentRow(
          'You will Receive',
          NumberFormatService.formatUsd(result.principal),
        ),
        PaymentRow(
          'Fee '
          '(${NumberFormatService.formatUsd(result.fiatFee)})',
          NumberFormatService.formatNumber(result.feeGold, decimals: 6),
        ),
        PaymentRow(
          'Total Sold',
          NumberFormatService.formatNumber(result.quantity, decimals: 6),
        ),
        PaymentRow(
          'Total Received',
          NumberFormatService.formatUsd(result.fiatPaid),
          isBold: true,
        ),
      ],
    );
  }

  Future<void> _showReceipt() async {
    final state = ref.read(goldTransactionProvider);

    final result = state.result;

    if (result == null) {
      return;
    }

    await DialogService.paymentReceipt(
      context,
      title: 'Gold Sold Successfully',
      rows: [
        PaymentRow(
          'Received',
          NumberFormatService.formatUsd(result.principal),
          type: PaymentRowType.amount,
        ),
        PaymentRow(
          'Fee',
          NumberFormatService.formatNumber(result.feeGold, decimals: 6),
          type: PaymentRowType.amount,
        ),
        PaymentRow(
          'Total Sold',
          NumberFormatService.formatNumber(result.quantity, decimals: 6),
        ),
        PaymentRow(
          'Total Received',
          NumberFormatService.formatUsd(result.fiatPaid),
          isBold: true,
        ),
      ],
      onDone: () {},
    );
  }
}

class _RefreshableState extends StatelessWidget {
  final Widget child;
  final Future<void> Function() onRefresh;

  const _RefreshableState({required this.child, required this.onRefresh});

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: onRefresh,
      triggerMode: RefreshIndicatorTriggerMode.anywhere,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          SizedBox(
            height: MediaQuery.sizeOf(context).height * 0.65,
            child: Center(child: child),
          ),
        ],
      ),
    );
  }
}
