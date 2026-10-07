import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:ngoda/data_models/payment/payment_row.dart';
import 'package:ngoda/services/dialog_service.dart';
import 'package:ngoda/services/number_format_service.dart';
import 'package:ngoda/ui/enums/enums.dart';
import 'package:ngoda/ui/extensions/app_size.dart';
import 'package:ngoda/ui/functions/refresh_user_dashboard.dart';
import 'package:ngoda/ui/screens/finance/providers/transactions_config_provider.dart';
import 'package:ngoda/ui/screens/wallet/gold/provider/gold_transaction_provider.dart';
import 'package:ngoda/ui/screens/wallet/transactions/provider/customer_transaction_setup_provider.dart';
import 'package:ngoda/ui/shared/app_colors.dart';
import 'package:ngoda/ui/shared/app_text_styles.dart';
import 'package:ngoda/ui/widgets/app_button.dart';
import 'package:ngoda/ui/widgets/app_error_state.dart';
import 'package:ngoda/ui/widgets/app_loader.dart';
import 'package:ngoda/ui/widgets/app_value_row.dart';
import 'package:ngoda/ui/widgets/input_field.dart';
import 'package:ngoda/ui/widgets/payment_calculation_card.dart';
import 'package:ngoda/ui/widgets/screen_header.dart';
import 'package:ngoda/ui/extensions/theme_extension.dart';

class TransferGoldScreen extends ConsumerStatefulWidget {
  const TransferGoldScreen({super.key});

  @override
  ConsumerState<TransferGoldScreen> createState() => _TransferGoldScreenState();
}

class _TransferGoldScreenState extends ConsumerState<TransferGoldScreen> {
  late final TextEditingController _emailController;
  late final TextEditingController _amountController;

  @override
  void initState() {
    super.initState();

    _emailController = TextEditingController();
    _amountController = TextEditingController();

    Future.microtask(() {
      if (!mounted) {
        return;
      }

      ref.read(goldTransactionProvider.notifier).initTransfer();
    });
  }

  @override
  void dispose() {
    _emailController.dispose();
    _amountController.dispose();

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final setupAsync = ref.watch(customerTransactionSetupProvider);

    final state = ref.watch(goldTransactionProvider);

    final notifier = ref.read(goldTransactionProvider.notifier);

    final spacing = context.spacing;
    final radius = context.radius;
    final colorScheme = context.colorScheme;

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            const ScreenHeader(
              title: 'Transfer Gold',
              subtitle: 'Send gold securely',
            ),

            Expanded(
              child: setupAsync.when(
                loading: () => const AppLoader(
                  message: 'Loading gold balance',
                  fullScreen: false,
                ),
                error: (error, _) {
                  return AppErrorState(
                    title: 'Unable to transfer gold',
                    message: error.toString(),
                  );
                },
                data: (setup) {
                  /*
                   * This is already the
                   * CustomerTransactionSetup
                   * snapshot.
                   */
                  final balance = setup.balances['gold'] ?? 0.0;

                  return GestureDetector(
                    behavior: HitTestBehavior.translucent,
                    onTap: () {
                      FocusScope.of(context).unfocus();
                    },
                    child: SingleChildScrollView(
                      keyboardDismissBehavior:
                          ScrollViewKeyboardDismissBehavior.onDrag,
                      padding: EdgeInsets.all(spacing.padding),
                      child: Column(
                        children: [
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
                                Text(
                                  'Transfer Details',
                                  style: AppTextStyles.medium(
                                    context,
                                  ).copyWith(fontWeight: FontWeight.w600),
                                ),

                                SizedBox(height: spacing.lg),

                                InputField(
                                  controller: _emailController,
                                  placeholder: 'Recipient Email',
                                  keyboardType: TextInputType.emailAddress,
                                  onChanged: notifier.updateEmail,
                                ),

                                SizedBox(height: spacing.sm),

                                InputField(
                                  controller: _amountController,
                                  placeholder: 'Gold Amount',
                                  keyboardType:
                                      const TextInputType.numberWithOptions(
                                        decimal: true,
                                      ),
                                  onChanged: (value) {
                                    _updateAmount(value, balance);
                                  },
                                  maxLength: 4,
                                ),

                                SizedBox(height: spacing.sm),

                                Container(
                                  width: double.infinity,
                                  padding: EdgeInsets.all(spacing.padding),
                                  decoration: BoxDecoration(
                                    color: colorScheme.surfaceContainer,
                                    borderRadius: BorderRadius.circular(
                                      radius.borderRadius,
                                    ),
                                    border: Border.all(
                                      color: colorScheme.outlineVariant
                                          .withValues(alpha: 0.09),
                                    ),
                                  ),
                                  child: AppValueRow(
                                    label: 'Available Gold',
                                    value: NumberFormatService.formatNumber(
                                      balance,
                                      decimals: 6,
                                    ),
                                    valueStyle: AppTextStyles.smallNumber(
                                      context,
                                    ).copyWith(fontWeight: FontWeight.w700),
                                    addBottomSpacing: false,
                                  ),
                                ),

                                if (state.amount > 0) ...[
                                  SizedBox(height: spacing.md),

                                  _buildCalculation(),
                                ],
                              ],
                            ),
                          ),

                          SizedBox(height: spacing.lg),

                          Row(
                            children: [
                              Expanded(
                                child: AppButton(
                                  text: 'Cancel',
                                  isPrimary: false,
                                  isDisabled: state.isLoading,
                                  onPressed: state.isLoading
                                      ? null
                                      : () {
                                          _emailController.clear();

                                          _amountController.clear();

                                          notifier.reset();

                                          context.pop();
                                        },
                                ),
                              ),

                              SizedBox(width: spacing.md),

                              Expanded(
                                child: AppButton(
                                  text: 'Transfer',
                                  isProcessing: state.isLoading,
                                  isDisabled: !state.isValid || state.isLoading,
                                  onPressed: !state.isValid || state.isLoading
                                      ? null
                                      : _handleTransfer,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _updateAmount(String value, double balance) {
    final configResponse = ref.read(transactionsConfigProvider).value;

    if (configResponse == null) {
      return;
    }

    final feeConfig = configResponse.result?.get('gold_token_transfer', 'gold');

    if (feeConfig == null) {
      return;
    }

    ref
        .read(goldTransactionProvider.notifier)
        .updateAmount(
          value,
          balance: balance,
          feeConfig: feeConfig,
          currency: 'gold',
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
          label: 'Amount',
          value: NumberFormatService.formatNumber(state.amount, decimals: 6),
          addBottomSpacing: false,
        ),

        SizedBox(height: context.spacing.sm),

        AppValueRow(
          label: 'Fee',
          value: NumberFormatService.formatNumber(result.feeGold, decimals: 6),
          addBottomSpacing: false,
        ),

        Padding(
          padding: EdgeInsets.symmetric(vertical: context.spacing.sm),
          child: const Divider(),
        ),

        AppValueRow(
          label: 'Total',
          value: NumberFormatService.formatNumber(result.quantity, decimals: 6),
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

  Future<void> _handleTransfer() async {
    try {
      final confirmed = await _confirmTransfer();

      if (confirmed != true) {
        return;
      }

      final notifier = ref.read(goldTransactionProvider.notifier);

      await notifier.goldTransfer();

      refreshUserDashboard(ref);

      if (!mounted) {
        return;
      }

      await _showReceipt();

      _emailController.clear();
      _amountController.clear();

      notifier.reset();
    } catch (error) {
      if (!mounted) {
        return;
      }

      await DialogService.error(context, message: error.toString());
    }
  }

  Future<bool?> _confirmTransfer() {
    final state = ref.read(goldTransactionProvider);

    final result = state.result;

    if (result == null) {
      return Future.value(false);
    }

    return DialogService.paymentConfirmation(
      context,
      title: 'Confirm Gold Transfer',
      rows: [
        PaymentRow('Recipient', state.email),
        PaymentRow(
          'Amount',
          NumberFormatService.formatNumber(state.amount, decimals: 6),
        ),
        PaymentRow(
          'Fee',
          NumberFormatService.formatNumber(result.feeGold, decimals: 6),
        ),
        PaymentRow(
          'Total',
          NumberFormatService.formatNumber(result.quantity, decimals: 6),
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
      title: 'Gold Transfer Successful',
      rows: [
        PaymentRow('Recipient', state.email),
        PaymentRow(
          'Amount',
          NumberFormatService.formatNumber(state.amount, decimals: 6),
          type: PaymentRowType.amount,
        ),
        PaymentRow(
          'Fee',
          NumberFormatService.formatNumber(result.feeGold, decimals: 6),
          type: PaymentRowType.amount,
        ),
        PaymentRow(
          'Total',
          NumberFormatService.formatNumber(result.quantity, decimals: 6),
          isBold: true,
        ),
      ],
      onDone: () {},
    );
  }
}
