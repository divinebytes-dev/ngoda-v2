import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:ngoda/data_models/loan/active_loan.dart';
import 'package:ngoda/services/number_format_service.dart';
import 'package:ngoda/ui/extensions/app_size.dart';
import 'package:ngoda/ui/extensions/theme_extension.dart';
import 'package:ngoda/ui/screens/wallet/loan/provider/active_loan_provider.dart';
import 'package:ngoda/ui/shared/app_text_styles.dart';
import 'package:ngoda/ui/widgets/app_empty_state.dart';
import 'package:ngoda/ui/widgets/app_error_state.dart';
import 'package:ngoda/ui/widgets/app_loader.dart';
import 'package:ngoda/ui/widgets/app_value_row.dart';
import 'package:ngoda/ui/widgets/view_header.dart';

class ActiveLoansScreen extends ConsumerWidget {
  const ActiveLoansScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final spacing = context.spacing;

    final asyncData = ref.watch(activeLoansProvider);

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: EdgeInsets.symmetric(horizontal: spacing.lg),
              child: ViewHeader(
                title: 'Active Value Accesses',
                onClose: context.pop,
              ),
            ),

            SizedBox(height: spacing.sm),

            Expanded(
              child: asyncData.when(
                loading: () => const Center(
                  child: AppLoader(
                    message: 'Loading active value accesses',
                    fullScreen: false,
                  ),
                ),
                error: (error, _) =>
                    AppErrorState(title: 'Error', message: error.toString()),
                data: (result) {
                  if (result.error != null) {
                    return AppErrorState(
                      title: 'Error',
                      message: result.error!,
                    );
                  }

                  final loans = result.result;

                  if (loans == null || loans.isEmpty) {
                    return const AppEmptyState();
                  }

                  return _LoanList(loans: loans);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LoanList extends StatelessWidget {
  const _LoanList({required this.loans});

  final List<ActiveLoan> loans;

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;

    return ListView.separated(
      padding: EdgeInsets.fromLTRB(
        spacing.lg,
        spacing.sm,
        spacing.lg,
        spacing.lg,
      ),
      itemCount: loans.length,
      separatorBuilder: (_, _) => SizedBox(height: spacing.md),
      itemBuilder: (context, index) {
        return _LoanCard(loan: loans[index]);
      },
    );
  }
}

class _LoanCard extends StatelessWidget {
  const _LoanCard({required this.loan});

  final ActiveLoan loan;

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    final colorScheme = Theme.of(context).colorScheme;

    final mutedLabelStyle = AppTextStyles.small(
      context,
    ).copyWith(color: colorScheme.onSurfaceVariant);

    return Material(
      color: Theme.of(context).cardColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(context.radius.lg),
        side: BorderSide(
          color: context.colorScheme.outlineVariant.withValues(alpha: 0.09),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () {
          context.push('/loans/active-loans/${loan.id}');
        },
        borderRadius: BorderRadius.circular(context.radius.lg),
        child: Padding(
          padding: EdgeInsets.all(spacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Outstanding Access Balance', style: mutedLabelStyle),

              SizedBox(height: spacing.xs),

              Text(
                NumberFormatService.formatAmount(
                  loan.outstandingBalance,
                  decimals: 2,
                ),
                style: AppTextStyles.mediumNumber(context),
              ),

              Divider(height: spacing.lg),

              AppValueRow(
                label: 'Access Balance',
                value: NumberFormatService.formatAmount(
                  loan.principal,
                  decimals: 2,
                ),
                labelStyle: mutedLabelStyle,
              ),

              AppValueRow(
                label: 'Liquidity Initiation Fee',
                value: NumberFormatService.formatAmount(
                  loan.initiationFee,
                  decimals: 2,
                ),
                labelStyle: mutedLabelStyle,
              ),

              AppValueRow(
                label: 'Accrued Liquidity Fee',
                value: NumberFormatService.formatAmount(
                  loan.accruedInterest,
                  decimals: 2,
                ),
                labelStyle: mutedLabelStyle,
              ),

              Divider(height: spacing.lg),

              AppValueRow(
                label: 'Collateral',
                value:
                    '${NumberFormatService.formatNumber(loan.collateralGrams, decimals: 6)} g',
                labelStyle: mutedLabelStyle,
              ),

              AppValueRow(
                label: 'Collateral Rebalancing Threshold',
                value: NumberFormatService.formatUsd(loan.liquidationPrice),
                labelStyle: mutedLabelStyle,
                addBottomSpacing: false,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
