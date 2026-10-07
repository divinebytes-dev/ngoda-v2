import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:ngoda/data_models/currency/currency.dart';
import 'package:ngoda/data_models/payment/payment_row.dart';
import 'package:ngoda/services/currency_service.dart';
import 'package:ngoda/services/dialog_service.dart';
import 'package:ngoda/services/number_format_service.dart';
import 'package:ngoda/ui/enums/enums.dart';
import 'package:ngoda/ui/extensions/app_size.dart';
import 'package:ngoda/ui/extensions/theme_extension.dart';
import 'package:ngoda/ui/functions/get_finance_balances.dart';
import 'package:ngoda/ui/screens/finance/providers/finance_dashboard_provider.dart';
import 'package:ngoda/ui/screens/finance/providers/finance_transaction_provider.dart';
import 'package:ngoda/ui/shared/app_colors.dart';
import 'package:ngoda/ui/widgets/app_button.dart';
import 'package:ngoda/ui/widgets/app_value_row.dart';
import 'package:ngoda/ui/widgets/input_field.dart';
import 'package:ngoda/ui/widgets/payment_calculation_card.dart';
import 'package:ngoda/ui/widgets/view_header.dart';

class GoldPurchaseScreen extends ConsumerStatefulWidget {
  const GoldPurchaseScreen({super.key});

  @override
  ConsumerState<GoldPurchaseScreen> createState() => _GoldPurchaseScreenState();
}

class _GoldPurchaseScreenState extends ConsumerState<GoldPurchaseScreen> {
  final quantityCtrl = TextEditingController();
  final priceCtrl = TextEditingController();
  final serialNumberCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();

    Future.microtask(() {
      final summary = ref.read(financeDashboardProvider).value;

      final balances = getTreasuryBalances(summary?.result);

      final Currency? currency = CurrencyService.get('usd');

      final balance = balances['usd'] ?? 0;

      ref
          .read(financeTransactionProvider.notifier)
          .initBalance(balance, currency);
    });
  }

  @override
  void dispose() {
    quantityCtrl.dispose();
    priceCtrl.dispose();
    serialNumberCtrl.dispose();

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    final radius = context.radius;
    final colorScheme = context.colorScheme;

    final state = ref.watch(financeTransactionProvider);

    final notifier = ref.read(financeTransactionProvider.notifier);

    return Scaffold(
      body: SafeArea(
        child: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTap: () {
            FocusScope.of(context).unfocus();
          },
          child: Column(
            children: [
              ViewHeader(
                title: 'Gold Purchase',
                onClose: () {
                  _reset();
                  context.pop();
                },
              ),
              Expanded(
                child: SingleChildScrollView(
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  padding: EdgeInsets.all(spacing.padding),
                  child: Container(
                    width: double.infinity,
                    padding: EdgeInsets.all(spacing.padding),
                    decoration: BoxDecoration(
                      color: colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(radius.borderRadius),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        InputField(
                          controller: quantityCtrl,
                          placeholder: 'Quantity',
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          onChanged: notifier.updateGoldQty,
                        ),
                        SizedBox(height: spacing.sm),
                        InputField(
                          controller: priceCtrl,
                          placeholder: 'Price',
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          onChanged: notifier.updateGoldPrice,
                        ),
                        SizedBox(height: spacing.sm),
                        InputField(
                          controller: serialNumberCtrl,
                          placeholder: 'Serial Number',
                          keyboardType: TextInputType.text,
                          onChanged: notifier.updateGoldSerial,
                        ),
                        if (state.currency != null) ...[
                          SizedBox(height: spacing.sm),
                          _buildCalculation(context),
                        ],
                        SizedBox(height: spacing.lg),
                        Row(
                          children: [
                            Expanded(
                              child: AppButton(
                                text: 'Cancel',
                                isPrimary: false,
                                isDisabled: state.isLoading,
                                onPressed: () {
                                  _reset();
                                  context.pop();
                                },
                              ),
                            ),
                            SizedBox(width: spacing.sm),
                            Expanded(
                              child: AppButton(
                                text: 'Purchase',
                                isProcessing: state.isLoading,
                                onPressed: !state.isValid || state.isLoading
                                    ? null
                                    : _handleGoldPurchase,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCalculation(BuildContext context) {
    final state = ref.read(financeTransactionProvider);

    final currency = state.currency?.code ?? 'usd';

    return PaymentCalculationCard(
      error: state.error,
      children: [
        AppValueRow(
          label: 'Available Balance',
          value: NumberFormatService.formatAmount(
            state.balance,
            currency: currency,
          ),
        ),
        AppValueRow(
          label: 'Total Debit',
          value: NumberFormatService.formatAmount(
            state.totalDebit,
            currency: currency,
          ),
          valueStyle: const TextStyle(fontWeight: FontWeight.w700),
        ),
        AppValueRow(
          label: 'New Balance',
          value: NumberFormatService.formatAmount(
            state.remaining,
            currency: currency,
          ),
          valueStyle: const TextStyle(fontWeight: FontWeight.w700),
          valueColor: state.remaining < 0 ? AppColors.error : AppColors.success,
          addBottomSpacing: false,
        ),
      ],
    );
  }

  Future<void> _handleGoldPurchase() async {
    try {
      final confirmed = await _confirmPurchase();

      if (confirmed != true) {
        return;
      }

      if (!mounted) {
        return;
      }

      final notifier = ref.read(financeTransactionProvider.notifier);

      await notifier.goldPurchase();

      ref.invalidate(financeDashboardProvider);

      if (!mounted) {
        return;
      }

      _showReceipt();

      quantityCtrl.clear();
      priceCtrl.clear();
      serialNumberCtrl.clear();

      notifier.reset();
    } catch (error) {
      if (!mounted) {
        return;
      }

      await DialogService.error(context, message: error.toString());
    }
  }

  Future<bool?> _confirmPurchase() {
    final state = ref.read(financeTransactionProvider);

    return DialogService.paymentConfirmation(
      context,
      title: 'Confirm Gold Purchase',
      rows: [
        PaymentRow(
          'Quantity',
          NumberFormatService.formatNumber(state.grams),
          isBold: true,
        ),
        PaymentRow(
          'Price',
          NumberFormatService.formatAmount(
            state.price,
            currency: state.currency?.code ?? 'usd',
          ),
        ),
        PaymentRow(
          'Serial Number',
          state.serialNumber,
          type: PaymentRowType.text,
        ),
      ],
    );
  }

  void _showReceipt() {
    final state = ref.read(financeTransactionProvider);

    DialogService.paymentReceipt(
      context,
      title: 'Gold Purchase Successful',
      rows: [
        PaymentRow('Serial', state.serialNumber, type: PaymentRowType.text),
        PaymentRow(
          'Quantity',
          NumberFormatService.formatNumber(state.amount),
          type: PaymentRowType.amount,
        ),
        PaymentRow(
          'Price',
          NumberFormatService.formatAmount(
            state.price,
            currency: state.currency?.code ?? 'usd',
          ),
          type: PaymentRowType.amount,
        ),
        PaymentRow(
          'Total',
          NumberFormatService.formatAmount(
            state.totalDebit,
            currency: state.currency?.code ?? 'usd',
          ),
          type: PaymentRowType.amount,
          isBold: true,
        ),
      ],
      onDone: () {},
    );
  }

  void _reset() {
    quantityCtrl.clear();
    priceCtrl.clear();
    serialNumberCtrl.clear();

    ref.read(financeTransactionProvider.notifier).reset();
  }
}
