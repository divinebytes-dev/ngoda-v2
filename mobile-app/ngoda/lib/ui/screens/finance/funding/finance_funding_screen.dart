import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:ngoda/services/calculation_service.dart';
import 'package:ngoda/services/number_format_service.dart';
import 'package:ngoda/ui/extensions/app_size.dart';
import 'package:ngoda/ui/extensions/theme_extension.dart';
import 'package:ngoda/ui/screens/finance/providers/finance_dashboard_provider.dart';
import 'package:ngoda/ui/shared/app_colors.dart';
import 'package:ngoda/ui/shared/app_text_styles.dart';
import 'package:ngoda/ui/widgets/action_tile.dart';
import 'package:ngoda/ui/widgets/bottom_nav.dart';

class FinanceFundingScreen extends ConsumerWidget {
  const FinanceFundingScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final spacing = context.spacing;
    final radius = context.radius;
    final colorScheme = context.colorScheme;

    final summary = ref.watch(financeDashboardProvider).value;

    final summaryResult = CalculationService.calculateFinanceSummary(
      summary?.result?.summary,
    );

    final balance = summaryResult.netPosition;

    return Scaffold(
      bottomNavigationBar: const BottomNav(currentIndex: 1),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: EdgeInsets.all(spacing.lg),
              child: Column(
                children: [
                  SizedBox(height: spacing.lg),
                  Text(
                    'Funding',
                    style: AppTextStyles.medium(
                      context,
                    ).copyWith(fontWeight: FontWeight.w700),
                  ),
                  SizedBox(height: spacing.xl),
                  Container(
                    width: double.infinity,
                    padding: EdgeInsets.all(spacing.lg),
                    decoration: BoxDecoration(
                      color: AppColors.darkPrimary.withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(radius.borderRadius),
                      border: Border.all(
                        color: AppColors.darkPrimary.withValues(alpha: 0.15),
                      ),
                    ),
                    child: Column(
                      children: [
                        Text(
                          'Balance',
                          style: AppTextStyles.small(
                            context,
                          ).copyWith(color: colorScheme.onSurfaceVariant),
                        ),
                        SizedBox(height: spacing.sm),
                        Text(
                          NumberFormatService.formatUsd(balance),
                          style: AppTextStyles.largeNumber(context).copyWith(
                            fontWeight: FontWeight.w800,
                            color: AppColors.darkPrimary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(
                  spacing.lg,
                  0,
                  spacing.lg,
                  spacing.lg,
                ),
                child: Column(
                  children: [
                    SizedBox(height: spacing.xl),
                    Container(
                      width: double.infinity,
                      padding: EdgeInsets.all(spacing.sm),
                      decoration: BoxDecoration(
                        color: colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(
                          radius.borderRadius,
                        ),
                      ),
                      child: Column(
                        children: [
                          ActionTile(
                            title: 'External Funds',
                            subtitle: 'Receive external funding',
                            icon: Icons.download_outlined,
                            color: Colors.green,
                            onTap: () {
                              context.push('/funding/external-funding');
                            },
                          ),
                          SizedBox(height: spacing.sm),
                          ActionTile(
                            title: 'Customer Direct Deposit',
                            subtitle: 'Customer direct deposit',
                            icon: Icons.wallet,
                            color: Colors.blue.shade500,
                            onTap: () {
                              context.push('/funding/customer-direct-deposit');
                            },
                          ),
                          SizedBox(height: spacing.sm),
                          ActionTile(
                            title: 'Gold Purchase',
                            subtitle: 'Record gold purchase',
                            icon: Icons.workspace_premium,
                            color: Colors.amber,
                            onTap: () {
                              context.push('/funding/gold-purchase');
                            },
                          ),
                        ],
                      ),
                    ),
                    SizedBox(height: spacing.xxxxl),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
