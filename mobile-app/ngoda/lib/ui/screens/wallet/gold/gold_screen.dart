import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:ngoda/services/number_format_service.dart';
import 'package:ngoda/ui/extensions/app_size.dart';
import 'package:ngoda/ui/extensions/theme_extension.dart';
import 'package:ngoda/ui/functions/get_current_user.dart';
import 'package:ngoda/ui/functions/gold_helper.dart';
import 'package:ngoda/ui/screens/wallet/transactions/provider/customer_transaction_setup_provider.dart';
import 'package:ngoda/ui/shared/app_colors.dart';
import 'package:ngoda/ui/shared/app_text_styles.dart';
import 'package:ngoda/ui/widgets/action_tile.dart';
import 'package:ngoda/ui/widgets/app_error_state.dart';
import 'package:ngoda/ui/widgets/app_loader.dart';
import 'package:ngoda/ui/widgets/bottom_nav.dart';
import 'package:ngoda/ui/widgets/gold_card.dart';
import 'package:ngoda/ui/widgets/screen_header.dart';

class GoldScreen extends ConsumerWidget {
  const GoldScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final spacing = context.spacing;
    final colorScheme = context.colorScheme;

    final user = getCurrentUser();

    final setupAsync = ref.watch(customerTransactionSetupProvider);

    return Scaffold(
      bottomNavigationBar: const BottomNav(currentIndex: 2),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(
                spacing.margin,
                spacing.margin,
                spacing.margin,
                0,
              ),
              child: const ScreenHeader(title: 'Gold'),
            ),

            Expanded(
              child: setupAsync.when(
                loading: () => const AppLoader(message: 'Loading gold balance'),
                error: (error, _) {
                  return AppErrorState(
                    title: 'Unable to load gold',
                    message: error.toString(),
                  );
                },
                data: (setup) {
                  /*
                   * customerTransactionSetupProvider
                   * already converts the role-specific
                   * dashboard into the transaction
                   * snapshot needed by wallet flows.
                   *
                   * Do not unwrap another result here.
                   */
                  final goldBalance = setup.balances['gold'] ?? 0.0;

                  final gold = computeGoldMetrics(setup.loanSummary);

                  return SingleChildScrollView(
                    padding: EdgeInsets.all(spacing.margin),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (user.role != 'customer')
                          GoldCard(
                            totalGrams: gold.total,
                            totalUsd: gold.totalUsd,
                            locked: gold.locked,
                            lockedUsd: gold.lockedUsd,
                            available: gold.available,
                            availableUsd: gold.availableUsd,
                          )
                        else
                          _CustomerGoldBalanceCard(goldBalance: goldBalance),

                        SizedBox(height: spacing.lg),

                        SizedBox(height: spacing.lg),

                        Text(
                          'Gold Actions',
                          style: AppTextStyles.small(
                            context,
                          ).copyWith(fontWeight: FontWeight.w600),
                        ),

                        SizedBox(height: spacing.sm),

                        ActionTile(
                          title: 'Buy Gold',
                          subtitle: 'Purchase gold using your wallet balance',
                          icon: Icons.arrow_downward_rounded,
                          color: AppColors.success,
                          iconShape: ActionTileIconShape.rounded,
                          onTap: () {
                            context.push('/gold/buy');
                          },
                        ),

                        SizedBox(height: spacing.sm),

                        ActionTile(
                          title: 'Transfer Gold',
                          subtitle: 'Send gold to another Ngoda user',
                          icon: Icons.send_rounded,
                          color: colorScheme.primary,
                          iconShape: ActionTileIconShape.rounded,
                          onTap: () {
                            context.push('/gold/transfer');
                          },
                        ),

                        SizedBox(height: spacing.sm),

                        ActionTile(
                          title: 'Sell Gold',
                          subtitle:
                              'Sell gold and receive funds in your wallet',
                          icon: Icons.arrow_upward_rounded,
                          color: AppColors.error,
                          iconShape: ActionTileIconShape.rounded,
                          onTap: () {
                            context.push('/gold/sell');
                          },
                        ),
                      ],
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
}

class _CustomerGoldBalanceCard extends StatelessWidget {
  const _CustomerGoldBalanceCard({required this.goldBalance});

  final double goldBalance;

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    final radius = context.radius;
    final colorScheme = context.colorScheme;

    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(spacing.lg),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(radius.cardRadius),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.09),
        ),
      ),
      child: Column(
        children: [
          Text(
            'Gold Balance',
            style: AppTextStyles.small(context).copyWith(
              color: colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w500,
            ),
          ),

          SizedBox(height: spacing.sm),

          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Flexible(
                child: Text(
                  NumberFormatService.formatNumber(goldBalance, decimals: 6),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.largeNumber(context).copyWith(
                    fontWeight: FontWeight.w800,
                    color: AppColors.darkPrimary,
                  ),
                ),
              ),

              SizedBox(width: spacing.xs),

              Text(
                'g',
                style: AppTextStyles.small(context).copyWith(
                  color: colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ActionItem extends StatelessWidget {
  const _ActionItem({
    required this.title,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  final String title;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    final radius = context.radius;
    final iconSize = context.iconSize;
    final colorScheme = context.colorScheme;

    return Material(
      color: context.theme.cardColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(radius.cardRadius),
        side: BorderSide(
          color: colorScheme.outlineVariant.withValues(alpha: 0.09),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(radius.cardRadius),
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: spacing.sm,
            vertical: spacing.md,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: EdgeInsets.all(spacing.sm),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(radius.borderRadius),
                ),
                child: Icon(icon, color: color, size: iconSize.medium),
              ),

              SizedBox(height: spacing.sm),

              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyles.tiny(context).copyWith(
                  fontWeight: FontWeight.w600,
                  color: colorScheme.onSurface,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// import 'package:flutter/material.dart';
// import 'package:flutter_riverpod/flutter_riverpod.dart';
// import 'package:go_router/go_router.dart';
// import 'package:ngoda/services/number_format_service.dart';
// import 'package:ngoda/ui/extensions/app_size.dart';
// import 'package:ngoda/ui/extensions/theme_extension.dart';
// import 'package:ngoda/ui/functions/get_current_user.dart';
// import 'package:ngoda/ui/functions/gold_helper.dart';
// import 'package:ngoda/ui/screens/wallet/transactions/provider/customer_transaction_setup_provider.dart';
// import 'package:ngoda/ui/shared/app_colors.dart';
// import 'package:ngoda/ui/shared/app_text_styles.dart';
// import 'package:ngoda/ui/widgets/app_error_state.dart';
// import 'package:ngoda/ui/widgets/app_loader.dart';
// import 'package:ngoda/ui/widgets/bottom_nav.dart';
// import 'package:ngoda/ui/widgets/gold_card.dart';
// import 'package:ngoda/ui/widgets/screen_header.dart';

// class GoldScreen extends ConsumerWidget {
//   const GoldScreen({super.key});

//   @override
//   Widget build(BuildContext context, WidgetRef ref) {
//     final spacing = context.spacing;
//     final radius = context.radius;
//     final colorScheme = context.colorScheme;

//     final user = getCurrentUser();

//     final setupAsync = ref.watch(customerTransactionSetupProvider);

//     return Scaffold(
//       bottomNavigationBar: const BottomNav(currentIndex: 2),
//       body: SafeArea(
//         child: setupAsync.when(
//           loading: () => const AppLoader(message: 'Loading gold balance'),
//           error: (error, _) => AppErrorState(
//             title: 'Unable to load gold',
//             message: error.toString(),
//           ),
//           data: (setup) {
//             /*
//              * customerTransactionSetupProvider
//              * already converts the role-specific
//              * dashboard into the transaction
//              * snapshot needed by wallet flows.
//              *
//              * Do not unwrap another result here.
//              */
//             final goldBalance = setup.balances['gold'] ?? 0.0;

//             final gold = computeGoldMetrics(setup.loanSummary);

//             return Padding(
//               padding: EdgeInsets.all(spacing.lg),
//               child: Column(
//                 children: [
//                   const ScreenHeader(title: 'Gold'),

//                   if (user.role != 'customer')
//                     GoldCard(
//                       totalGrams: gold.total,
//                       totalUsd: gold.totalUsd,
//                       locked: gold.locked,
//                       lockedUsd: gold.lockedUsd,
//                       available: gold.available,
//                       availableUsd: gold.availableUsd,
//                     )
//                   else
//                     Container(
//                       width: double.infinity,
//                       padding: EdgeInsets.symmetric(
//                         vertical: spacing.lg,
//                         horizontal: spacing.lg,
//                       ),
//                       decoration: BoxDecoration(
//                         color: context.theme.cardColor,
//                         borderRadius: BorderRadius.circular(radius.md),
//                         border: Border.all(
//                           color: AppColors.darkPrimary.withValues(alpha: 0.4),
//                         ),
//                       ),
//                       child: Column(
//                         children: [
//                           Text('Balance', style: AppTextStyles.small(context)),
//                           SizedBox(height: spacing.sm),
//                           Text(
//                             NumberFormatService.formatNumber(
//                               goldBalance,
//                               decimals: 6,
//                             ),
//                             style: AppTextStyles.largeNumber(context).copyWith(
//                               fontWeight: FontWeight.w800,
//                               color: AppColors.darkPrimary,
//                             ),
//                           ),
//                         ],
//                       ),
//                     ),

//                   SizedBox(height: spacing.xl),

//                   Container(
//                     padding: EdgeInsets.all(spacing.sm),
//                     decoration: BoxDecoration(
//                       color: context.theme.cardColor,
//                       borderRadius: BorderRadius.circular(radius.md),
//                     ),
//                     child: Row(
//                       children: [
//                         Expanded(
//                           child: _ActionItem(
//                             title: 'Buy',
//                             icon: Icons.arrow_downward,
//                             color: AppColors.success,
//                             onTap: () {
//                               context.push('/gold/buy');
//                             },
//                           ),
//                         ),
//                         SizedBox(width: spacing.sm),
//                         Expanded(
//                           child: _ActionItem(
//                             title: 'Transfer',
//                             icon: Icons.send,
//                             color: colorScheme.primary,
//                             onTap: () {
//                               context.push('/gold/transfer');
//                             },
//                           ),
//                         ),
//                         SizedBox(width: spacing.sm),
//                         Expanded(
//                           child: _ActionItem(
//                             title: 'Sell',
//                             icon: Icons.arrow_upward,
//                             color: AppColors.error,
//                             onTap: () {
//                               context.push('/gold/sell');
//                             },
//                           ),
//                         ),
//                       ],
//                     ),
//                   ),
//                 ],
//               ),
//             );
//           },
//         ),
//       ),
//     );
//   }
// }

// class _ActionItem extends StatelessWidget {
//   final String title;
//   final IconData icon;
//   final Color color;
//   final VoidCallback onTap;

//   const _ActionItem({
//     required this.title,
//     required this.icon,
//     required this.color,
//     required this.onTap,
//   });

//   @override
//   Widget build(BuildContext context) {
//     final spacing = context.spacing;
//     final radius = context.radius;
//     final iconSize = context.iconSize;

//     return InkWell(
//       borderRadius: BorderRadius.circular(radius.sm),
//       onTap: onTap,
//       child: Container(
//         padding: EdgeInsets.symmetric(vertical: spacing.sm),
//         decoration: BoxDecoration(
//           color: context.theme.cardColor,
//           borderRadius: BorderRadius.circular(radius.sm),
//           border: Border.all(color: color.withValues(alpha: 0.4)),
//         ),
//         child: Column(
//           mainAxisSize: MainAxisSize.min,
//           children: [
//             Icon(icon, color: color, size: iconSize.small),
//             SizedBox(height: spacing.xs),
//             Text(
//               title,
//               style: AppTextStyles.tiny(
//                 context,
//               ).copyWith(fontWeight: FontWeight.w600, color: color),
//             ),
//           ],
//         ),
//       ),
//     );
//   }
// }
