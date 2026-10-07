import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:ngoda/services/number_format_service.dart';
import 'package:ngoda/ui/extensions/app_size.dart';
import 'package:ngoda/ui/extensions/theme_extension.dart';
import 'package:ngoda/ui/screens/wallet/loan/provider/loan_transaction_provider.dart';
import 'package:ngoda/ui/screens/wallet/transactions/provider/customer_transaction_setup_provider.dart';
import 'package:ngoda/ui/shared/app_text_styles.dart';
import 'package:ngoda/ui/widgets/app_button.dart';
import 'package:ngoda/ui/widgets/app_error_state.dart';
import 'package:ngoda/ui/widgets/app_loader.dart';
import 'package:ngoda/ui/widgets/input_field.dart';
import 'package:ngoda/ui/widgets/view_header.dart';

class BorrowLoanScreen extends ConsumerStatefulWidget {
  const BorrowLoanScreen({super.key});

  @override
  ConsumerState<BorrowLoanScreen> createState() => _BorrowLoanScreenState();
}

class _BorrowLoanScreenState extends ConsumerState<BorrowLoanScreen> {
  final TextEditingController amountController = TextEditingController();

  @override
  void initState() {
    super.initState();

    /*
     * Each access-value flow must start
     * with a fresh transaction reference.
     */
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }

      ref.read(loanTransactionProvider.notifier).reset();
    });
  }

  @override
  void dispose() {
    amountController.dispose();

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;

    final dashboardAsync = ref.watch(customerTransactionSetupProvider);

    final transactionState = ref.watch(loanTransactionProvider);

    return Scaffold(
      body: SafeArea(
        child: GestureDetector(
          onTap: () => FocusScope.of(context).unfocus(),
          child: Padding(
            padding: EdgeInsets.all(spacing.lg),
            child: dashboardAsync.when(
              loading: () => const AppLoader(),

              error: (error, _) => AppErrorState(
                message: error.toString(),
                onAction: () => context.pop(),
              ),

              data: (transactionSetup) {
                final availableGold =
                    transactionSetup.loanSummary.gold.available.grams;

                return SingleChildScrollView(
                  child: Column(
                    children: [
                      ViewHeader(
                        title: 'Access Value',
                        subtitle: 'Use your gold as collateral to access value',
                        onClose: context.pop,
                      ),

                      SizedBox(height: spacing.lg),

                      _AvailableGoldCard(availableGold: availableGold),

                      SizedBox(height: spacing.lg),
                      Container(
                        padding: EdgeInsets.symmetric(
                          horizontal: context.spacing.sm,
                          vertical: context.spacing.padding,
                        ),
                        decoration: BoxDecoration(
                          color: context.theme.cardColor,
                          borderRadius: BorderRadius.circular(
                            context.radius.cardRadius,
                          ),
                          border: Border.all(
                            color: context.colorScheme.outlineVariant
                                .withValues(alpha: 0.09),
                          ),
                        ),
                        child: Column(
                          children: [
                            InputField(
                              controller: amountController,
                              placeholder: 'Access amount',
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),
                              onChanged: (value) {
                                final amount = NumberFormatService.anyToDouble(
                                  value.trim(),
                                );

                                ref
                                    .read(loanTransactionProvider.notifier)
                                    .updateAmount(amount);
                              },
                            ),
                            if (transactionState.error != null) ...[
                              SizedBox(height: spacing.sm),

                              Align(
                                alignment: Alignment.centerLeft,
                                child: Text(
                                  transactionState.error!,
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
                                    isDisabled: transactionState.isLoading,
                                    onPressed: () => _cancel(context),
                                  ),
                                ),

                                SizedBox(width: spacing.md),

                                Expanded(
                                  child: AppButton(
                                    text: 'Preview',
                                    isProcessing: transactionState.isLoading,
                                    onPressed:
                                        !transactionState.isValid ||
                                            transactionState.isLoading
                                        ? null
                                        : () => _preview(
                                            context,
                                            transactionState.amount,
                                          ),
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

  void _cancel(BuildContext context) {
    amountController.clear();

    ref.read(loanTransactionProvider.notifier).reset();

    context.pop();
  }

  void _preview(BuildContext context, double amount) {
    FocusScope.of(context).unfocus();

    context.push('/loans/borrow/loan-preview', extra: amount.toString());
  }
}

class _AvailableGoldCard extends StatelessWidget {
  const _AvailableGoldCard({required this.availableGold});

  final double availableGold;

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    final theme = Theme.of(context);

    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(spacing.lg),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(context.radius.cardRadius),
        border: Border.all(
          color: context.colorScheme.primary.withValues(alpha: 0.2),
        ),
      ),
      child: Column(
        children: [
          Text(
            'Available Gold',
            style: AppTextStyles.small(
              context,
            ).copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          SizedBox(height: spacing.sm),
          Text(
            '${NumberFormatService.formatNumber(availableGold, decimals: 8)} g',
            style: AppTextStyles.largeNumber(context).copyWith(
              fontWeight: FontWeight.w700,
              color: theme.colorScheme.primary,
            ),
          ),
        ],
      ),
    );
  }
}
