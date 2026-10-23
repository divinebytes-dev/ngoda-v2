import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:ngoda/services/number_format_service.dart';
import 'package:ngoda/ui/extensions/app_size.dart';
import 'package:ngoda/ui/extensions/theme_extension.dart';
import 'package:ngoda/ui/screens/accounts/providers/accounts_dashboard_provider.dart';
import 'package:ngoda/ui/shared/app_text_styles.dart';
import 'package:ngoda/ui/widgets/action_tile.dart';
import 'package:ngoda/ui/widgets/app_error_state.dart';
import 'package:ngoda/ui/widgets/app_loader.dart';
import 'package:ngoda/ui/widgets/bottom_nav.dart';

class AccountsFundingScreen extends ConsumerWidget {
  const AccountsFundingScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final spacing = context.spacing;
    final radius = context.radius;
    final colorScheme = context.colorScheme;

    final dashboardAsync = ref.watch(accountsDashboardProvider);

    return Scaffold(
      bottomNavigationBar: const BottomNav(currentIndex: 1),
      body: SafeArea(
        child: dashboardAsync.when(
          loading: () => const AppLoader(
            message: 'Loading funding balances',
            fullScreen: false,
          ),
          error: (error, _) {
            return AppErrorState(message: error.toString());
          },
          data: (response) {
            if (response.error != null) {
              return AppErrorState(message: response.error.toString());
            }

            final dashboard = response.result;

            return Column(
              children: [
                Padding(
                  padding: EdgeInsets.fromLTRB(
                    spacing.lg,
                    spacing.lg,
                    spacing.lg,
                    0,
                  ),
                  child: Column(
                    children: [
                      SizedBox(height: spacing.lg),
                      Center(
                        child: Text(
                          'Funding',
                          style: AppTextStyles.medium(
                            context,
                          ).copyWith(fontWeight: FontWeight.w700),
                        ),
                      ),
                      SizedBox(height: spacing.xl),

                      // Balance card
                      Container(
                        width: double.infinity,
                        padding: EdgeInsets.all(spacing.lg),
                        decoration: BoxDecoration(
                          color: colorScheme.surface,
                          borderRadius: BorderRadius.circular(
                            radius.borderRadius,
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              'Balances',
                              textAlign: TextAlign.center,
                              style: AppTextStyles.small(
                                context,
                              ).copyWith(color: colorScheme.onSurfaceVariant),
                            ),
                            SizedBox(height: spacing.md),
                            if (dashboard == null || dashboard.bankNet.isEmpty)
                              Text(
                                'No funding balances',
                                textAlign: TextAlign.center,
                                style: AppTextStyles.small(
                                  context,
                                ).copyWith(color: colorScheme.onSurfaceVariant),
                              )
                            else
                              ...dashboard.sortedBankNetCurrencyList.map((
                                currency,
                              ) {
                                return Padding(
                                  padding: EdgeInsets.symmetric(
                                    vertical: spacing.xs,
                                  ),
                                  child: Row(
                                    children: [
                                      Text(
                                        currency.toUpperCase(),
                                        style: AppTextStyles.small(context)
                                            .copyWith(
                                              color:
                                                  colorScheme.onSurfaceVariant,
                                            ),
                                      ),
                                      SizedBox(width: spacing.sm),
                                      Expanded(
                                        child: Text(
                                          NumberFormatService.formatAmount(
                                            dashboard.bankNetBalance(currency),
                                            currency: currency,
                                          ),
                                          textAlign: TextAlign.right,
                                          style:
                                              AppTextStyles.smallNumber(
                                                context,
                                              ).copyWith(
                                                color: colorScheme.primary,
                                                fontWeight: FontWeight.w700,
                                              ),
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              }),
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
                      spacing.lg,
                      spacing.lg,
                      spacing.lg,
                    ),
                    child: Column(
                      children: [
                        _ActionSection(
                          children: [
                            ActionTile(
                              title: 'Fund Treasury',
                              subtitle: 'Treasury funding',
                              icon: Icons.monetization_on_outlined,
                              color: colorScheme.primary,
                              onTap: () {
                                context.push(
                                  '/accounts-funding/treasury-funding',
                                );
                              },
                            ),
                          ],
                        ),
                        SizedBox(height: spacing.lg),
                        _ActionSection(
                          children: [
                            ActionTile(
                              title: 'Credit Agents Balances',
                              subtitle: 'Credit agents balances',
                              icon: Icons.account_balance_wallet_outlined,
                              color: colorScheme.primary,
                              onTap: () {
                                context.push(
                                  '/accounts-funding/credit-agents-balances',
                                );
                              },
                            ),
                            SizedBox(height: spacing.sm),
                            ActionTile(
                              title: 'Credit Agents Settlement',
                              subtitle: 'Credit agents balance settlement',
                              icon: Icons.payments_outlined,
                              color: colorScheme.primary,
                              onTap: () {
                                context.push(
                                  '/accounts-funding/credit-agent-cash-settlement',
                                );
                              },
                            ),
                          ],
                        ),
                        SizedBox(height: spacing.xxxxl),
                      ],
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _ActionSection extends StatelessWidget {
  const _ActionSection({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    final radius = context.radius;
    final colorScheme = context.colorScheme;

    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(spacing.sm),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(radius.borderRadius),
      ),
      child: Column(children: children),
    );
  }
}
