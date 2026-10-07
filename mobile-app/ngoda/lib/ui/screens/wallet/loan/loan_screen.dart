import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:ngoda/ui/extensions/app_size.dart';
import 'package:ngoda/ui/extensions/theme_extension.dart';
import 'package:ngoda/ui/screens/wallet/transactions/provider/customer_transaction_setup_provider.dart';
import 'package:ngoda/ui/widgets/action_tile.dart';
import 'package:ngoda/ui/widgets/app_error_state.dart';
import 'package:ngoda/ui/widgets/app_loader.dart';
import 'package:ngoda/ui/widgets/bottom_nav.dart';
import 'package:ngoda/ui/widgets/loan_card.dart';
import 'package:ngoda/ui/widgets/screen_header.dart';

class LoanScreen extends ConsumerWidget {
  const LoanScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final spacing = context.spacing;

    final dashboardAsync = ref.watch(customerTransactionSetupProvider);

    return Scaffold(
      bottomNavigationBar: const BottomNav(currentIndex: 3),
      body: SafeArea(
        child: Padding(
          padding: EdgeInsets.all(spacing.lg),
          child: dashboardAsync.when(
            loading: () => const AppLoader(),
            error: (error, _) => AppErrorState(message: error.toString()),
            data: (dashboard) {
              final loanSummary = dashboard.loanSummary;

              final svaAccess = loanSummary.svaAccess;

              final canAccessValue = svaAccess.canAccess;

              final canTopupCollateral = loanSummary.ltvPercent >= 65;

              return Column(
                children: [
                  const ScreenHeader(title: 'Secured Value Access'),
                  SizedBox(height: spacing.lg),
                  LoanCard(
                    principal: loanSummary.principalOutstanding,
                    interest: loanSummary.interestOutstanding,
                    ltv: loanSummary.ltvPercent,
                    requiredCollateral: loanSummary.requiredCollateral,
                    svaUtilisation: svaAccess.utilisationPercent,
                  ),
                  SizedBox(height: spacing.lg),
                  Expanded(
                    child: _LoanActions(
                      canAccessValue: canAccessValue,
                      canTopupCollateral: canTopupCollateral,
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _LoanActions extends StatelessWidget {
  const _LoanActions({
    required this.canAccessValue,
    required this.canTopupCollateral,
  });

  final bool canAccessValue;
  final bool canTopupCollateral;

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    final theme = Theme.of(context);

    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(spacing.md),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(context.radius.cardRadius),
        border: Border.all(
          color: context.colorScheme.outlineVariant.withValues(alpha: 0.09),
        ),
      ),
      child: SingleChildScrollView(
        child: Column(
          children: [
            ActionTile(
              title: 'Access Value',
              subtitle: 'Unlock liquidity without selling gold',
              icon: Icons.money,
              color: canAccessValue ? Colors.green : Colors.grey,
              onTap: canAccessValue
                  ? () => context.push('/loans/borrow')
                  : null,
            ),
            SizedBox(height: spacing.sm),
            ActionTile(
              title: 'Settle Balance',
              subtitle: 'Outstanding Access Balance Settlement',
              icon: Icons.monetization_on,
              color: Colors.orange,
              onTap: () => context.push('/loans/repay'),
            ),
            SizedBox(height: spacing.sm),
            ActionTile(
              title: 'Active Access Values',
              subtitle: 'Active Secured Value Access List',
              icon: Icons.list_alt,
              color: Colors.red.shade900,
              onTap: () => context.push('/loans/active-loans'),
            ),
            SizedBox(height: spacing.sm),
            ActionTile(
              title: 'Topup Loan Collateral',
              subtitle: 'Add collateral to risk loans',
              icon: Icons.account_balance_wallet_outlined,
              color: canTopupCollateral ? Colors.purple.shade900 : Colors.grey,
              onTap: canTopupCollateral
                  ? () => context.push('/loans/topup-collateral')
                  : null,
            ),
          ],
        ),
      ),
    );
  }
}
