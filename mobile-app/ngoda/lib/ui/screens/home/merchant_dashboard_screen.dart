import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:ngoda/core/providers/hive_service_provider.dart';
import 'package:ngoda/data_models/currency/currency_balance.dart';
import 'package:ngoda/data_models/merchant/credit_agent_currency_balance.dart';
import 'package:ngoda/services/hive_service.dart';
import 'package:ngoda/services/number_format_service.dart';
import 'package:ngoda/ui/enums/enums.dart';
import 'package:ngoda/ui/extensions/app_size.dart';
import 'package:ngoda/ui/extensions/theme_extension.dart';
import 'package:ngoda/ui/functions/compute_net_position.dart';
import 'package:ngoda/ui/functions/get_user_home_screen_quick_links.dart';
import 'package:ngoda/ui/functions/is_jwt_expired.dart';
import 'package:ngoda/ui/screens/auth/providers/auth_provider.dart';
import 'package:ngoda/ui/screens/home/vendor_dashboard_screen.dart';
import 'package:ngoda/ui/screens/merchant/provider/merchant_dashboard_provider.dart';
import 'package:ngoda/ui/shared/app_text_styles.dart';
import 'package:ngoda/ui/shared/theme_provider.dart';
import 'package:ngoda/ui/widgets/app_error_state.dart';
import 'package:ngoda/ui/widgets/app_loader.dart';
import 'package:ngoda/ui/widgets/bottom_nav.dart';
import 'package:ngoda/ui/widgets/dashboard_quick_actions.dart';
import 'package:ngoda/ui/widgets/fiat_card.dart';
import 'package:ngoda/ui/widgets/net_position_card.dart';

enum _MerchantWalletType { merchant, agent }

class MerchantDashboardScreen extends ConsumerStatefulWidget {
  const MerchantDashboardScreen({super.key});

  @override
  ConsumerState<MerchantDashboardScreen> createState() =>
      _MerchantDashboardScreenState();
}

class _MerchantDashboardScreenState
    extends ConsumerState<MerchantDashboardScreen> {
  _MerchantWalletType _selectedWallet = _MerchantWalletType.merchant;

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    final iconSize = context.iconSize;
    final colorScheme = context.colorScheme;

    final nfcSupported =
        ref
            .read(hiveServiceProvider)
            .getItem<bool>(HiveBoxName.nfcSupport, 'nfcSupported')
            .result ??
        false;

    final asyncData = ref.watch(merchantDashboardProvider);

    return asyncData.when(
      loading: () => const AppLoader(
        message: 'Loading merchant dashboard',
        fullScreen: true,
      ),
      error: (error, _) {
        if (isJwtExpired(error)) {
          return _SessionExpiredState(ref: ref);
        }

        return Scaffold(body: AppErrorState(message: error.toString()));
      },
      data: (response) {
        if (response.error != null) {
          if (isJwtExpired(response.error!)) {
            return _SessionExpiredState(ref: ref);
          }

          return Scaffold(body: AppErrorState(message: response.error!));
        }

        final dashboard = response.result;

        if (dashboard == null) {
          return const Scaffold(
            body: AppErrorState(
              title: 'Merchant Dashboard',
              message: 'Merchant dashboard is not available.',
            ),
          );
        }

        /*
         * Credit-agent capability comes from
         * the Merchant dashboard.
         */
        final quickLinks = getUserHomeScreenQuickLinks(
          context: context,
          role: UserRole.merchant,
          iconSize: iconSize.medium,
          primary: colorScheme.primary,
          nfcSupported: nfcSupported,
          isCreditAgent: dashboard.isCreditAgent,
        );

        final netPosition = computeMerchantNetPosition(dashboard);

        return Scaffold(
          bottomNavigationBar: const BottomNav(currentIndex: 0),
          body: SafeArea(
            child: RefreshIndicator(
              onRefresh: () async {
                ref.invalidate(merchantDashboardProvider);

                await ref.read(merchantDashboardProvider.future);
              },
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: EdgeInsets.fromLTRB(
                  spacing.padding,
                  spacing.md,
                  spacing.padding,
                  spacing.padding,
                ),
                children: [
                  _DashboardHeader(
                    themeMode: ref.watch(themeModeProvider),
                    onThemeChanged: () {
                      ref.read(themeModeProvider.notifier).toggle();
                    },
                  ),

                  SizedBox(height: spacing.md),

                  NetPositionCard(amount: netPosition),

                  if (quickLinks.isNotEmpty) ...[
                    SizedBox(height: spacing.md),
                    DashboardQuickActions(quickLinks: quickLinks),
                  ],

                  SizedBox(height: spacing.lg),

                  _WalletSelector(
                    selectedWallet: _selectedWallet,
                    onSelected: (wallet) {
                      if (_selectedWallet == wallet) {
                        return;
                      }

                      setState(() {
                        _selectedWallet = wallet;
                      });
                    },
                  ),

                  SizedBox(height: spacing.md),

                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 180),
                    child: _buildSelectedWallet(dashboard),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildSelectedWallet(dynamic dashboard) {
    final spacing = context.spacing;

    switch (_selectedWallet) {
      case _MerchantWalletType.merchant:
        return Column(
          key: const ValueKey(_MerchantWalletType.merchant),
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const _WalletHeading(
              title: 'Merchant Wallet',
              description: 'Funds received from customer payments.',
            ),

            SizedBox(height: spacing.sm),

            FiatCard(wallet: dashboard.merchantWallet),

            SizedBox(height: spacing.md),

            DailyPaymentSummaryCard(summary: dashboard.dailySummary),
          ],
        );

      case _MerchantWalletType.agent:
        return Column(
          key: const ValueKey(_MerchantWalletType.agent),
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const _WalletHeading(
              title: 'Agent Wallet',
              description: 'Float used for customer cash in and cash out.',
            ),

            SizedBox(height: spacing.sm),

            FiatCard(wallet: dashboard.agentWallet),

            if (dashboard.isCreditAgent) ...[
              SizedBox(height: spacing.lg),

              const _SectionHeading(
                title: 'Credit Agent Position',
                description:
                    'Cash collected and outstanding amounts related to credit-agent operations.',
              ),

              SizedBox(height: spacing.sm),

              CreditWalletSection(
                title: 'Cash Owed',
                subtitle: 'Cash collected and owed to treasury',
                wallet: dashboard.creditAgent,
                balanceSelector: (balance) => balance.cashOwed,
              ),

              SizedBox(height: spacing.md),

              CreditWalletSection(
                title: 'Receivable Balance',
                subtitle: 'Outstanding amount receivable',
                wallet: dashboard.creditAgent,
                balanceSelector: (balance) => balance.receivableBalance,
              ),
            ],

            SizedBox(height: spacing.md),

            DailySummaryCard(summary: dashboard.dailySummary),
          ],
        );
    }
  }
}

class _DashboardHeader extends StatelessWidget {
  const _DashboardHeader({
    required this.onThemeChanged,
    required this.themeMode,
  });

  final VoidCallback onThemeChanged;
  final ThemeMode themeMode;

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    final iconSize = context.iconSize;
    final colorScheme = context.colorScheme;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Welcome Back',
                style: AppTextStyles.large(
                  context,
                ).copyWith(fontWeight: FontWeight.w700),
              ),

              SizedBox(height: spacing.xs),

              Text(
                'Overview of your financial position',
                style: AppTextStyles.small(
                  context,
                ).copyWith(color: colorScheme.onSurfaceVariant),
              ),
            ],
          ),
        ),

        IconButton(
          tooltip: themeMode == ThemeMode.dark
              ? 'Use light theme'
              : 'Use dark theme',
          iconSize: iconSize.medium,
          onPressed: onThemeChanged,
          icon: Icon(
            themeMode == ThemeMode.dark ? Icons.light_mode : Icons.dark_mode,
            color: colorScheme.primary,
          ),
        ),
      ],
    );
  }
}

class _WalletSelector extends StatelessWidget {
  const _WalletSelector({
    required this.selectedWallet,
    required this.onSelected,
  });

  final _MerchantWalletType selectedWallet;

  final ValueChanged<_MerchantWalletType> onSelected;

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    final radius = context.radius;
    final colorScheme = context.colorScheme;

    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(spacing.xs),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(radius.cardRadius),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.09),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: _WalletTab(
              title: 'Merchant',
              selected: selectedWallet == _MerchantWalletType.merchant,
              onTap: () {
                onSelected(_MerchantWalletType.merchant);
              },
            ),
          ),

          SizedBox(width: spacing.xs),

          Expanded(
            child: _WalletTab(
              title: 'Agent',
              selected: selectedWallet == _MerchantWalletType.agent,
              onTap: () {
                onSelected(_MerchantWalletType.agent);
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _WalletTab extends StatelessWidget {
  const _WalletTab({
    required this.title,
    required this.selected,
    required this.onTap,
  });

  final String title;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    final radius = context.radius;
    final colorScheme = context.colorScheme;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(radius.borderRadius),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: EdgeInsets.symmetric(
            horizontal: spacing.sm,
            vertical: spacing.sm,
          ),
          decoration: BoxDecoration(
            color: selected ? context.theme.cardColor : Colors.transparent,
            borderRadius: BorderRadius.circular(radius.borderRadius),
            border: selected
                ? Border.all(color: colorScheme.primary.withValues(alpha: 0.20))
                : null,
          ),
          alignment: Alignment.center,
          child: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTextStyles.small(context).copyWith(
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              color: selected
                  ? colorScheme.primary
                  : colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ),
    );
  }
}

class _WalletHeading extends StatelessWidget {
  const _WalletHeading({required this.title, required this.description});

  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    final colorScheme = context.colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: AppTextStyles.small(
            context,
          ).copyWith(fontWeight: FontWeight.w700),
        ),

        SizedBox(height: spacing.xs),

        Text(
          description,
          style: AppTextStyles.tiny(
            context,
          ).copyWith(color: colorScheme.onSurfaceVariant),
        ),
      ],
    );
  }
}

class _SectionHeading extends StatelessWidget {
  const _SectionHeading({required this.title, required this.description});

  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    final colorScheme = context.colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: AppTextStyles.small(
            context,
          ).copyWith(fontWeight: FontWeight.w700),
        ),

        SizedBox(height: spacing.xs),

        Text(
          description,
          style: AppTextStyles.tiny(
            context,
          ).copyWith(color: colorScheme.onSurfaceVariant),
        ),
      ],
    );
  }
}

/* -------------------------------------------------------------------------- */
/*                            SESSION EXPIRED                                 */
/* -------------------------------------------------------------------------- */

class _SessionExpiredState extends StatelessWidget {
  const _SessionExpiredState({required this.ref});

  final WidgetRef ref;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: AppErrorState(
        title: 'Session Expired',
        message: 'Please login again to continue.',
        buttonText: 'Logout',
        onAction: () async {
          await ref.read(authProvider.notifier).logout('Session Expired');

          if (!context.mounted) {
            return;
          }

          context.go('/login');
        },
      ),
    );
  }
}

/* -------------------------------------------------------------------------- */
/*                         CREDIT AGENT WALLET                                */
/* -------------------------------------------------------------------------- */

typedef CreditAgentBalanceSelector =
    CurrencyBalance Function(CreditAgentCurrencyBalance balance);

class CreditWalletSection extends StatelessWidget {
  const CreditWalletSection({
    super.key,
    required this.title,
    required this.subtitle,
    required this.wallet,
    required this.balanceSelector,
  });

  final String title;
  final String subtitle;
  final CreditAgentWallet wallet;
  final CreditAgentBalanceSelector balanceSelector;

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    final colorScheme = context.colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: AppTextStyles.small(
            context,
          ).copyWith(fontWeight: FontWeight.w700),
        ),

        SizedBox(height: spacing.xs),

        Text(
          subtitle,
          style: AppTextStyles.tiny(
            context,
          ).copyWith(color: colorScheme.onSurfaceVariant),
        ),

        SizedBox(height: spacing.sm),

        CreditAgentBalanceCard(
          wallet: wallet,
          balanceSelector: balanceSelector,
        ),
      ],
    );
  }
}

/* -------------------------------------------------------------------------- */
/*                      CREDIT AGENT BALANCE CARD                             */
/* -------------------------------------------------------------------------- */

class CreditAgentBalanceCard extends StatelessWidget {
  const CreditAgentBalanceCard({
    super.key,
    required this.wallet,
    required this.balanceSelector,
  });

  final CreditAgentWallet wallet;
  final CreditAgentBalanceSelector balanceSelector;

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    final radius = context.radius;
    final colorScheme = context.colorScheme;

    final fiatEntries = wallet.currencyEntries
        .where((entry) => entry.key.toLowerCase() != 'gold')
        .toList();

    final totalUsd = fiatEntries.fold<double>(
      0,
      (sum, entry) => sum + balanceSelector(entry.value).usdValue,
    );

    return Container(
      padding: EdgeInsets.all(spacing.sm),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(radius.cardRadius),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.09),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Total Balance',
            style: AppTextStyles.small(
              context,
            ).copyWith(color: colorScheme.onSurfaceVariant),
          ),

          SizedBox(height: spacing.xs),

          Text(
            NumberFormatService.formatAmount(totalUsd, currency: 'usd'),
            style: AppTextStyles.largeNumber(
              context,
            ).copyWith(fontWeight: FontWeight.w700, color: colorScheme.primary),
          ),

          SizedBox(height: spacing.sm),

          Divider(color: colorScheme.outlineVariant.withValues(alpha: 0.45)),

          SizedBox(height: spacing.sm),

          Text(
            'Breakdown',
            style: AppTextStyles.small(
              context,
            ).copyWith(color: colorScheme.onSurfaceVariant),
          ),

          SizedBox(height: spacing.sm),

          for (final entry in fiatEntries)
            _CreditAgentBalanceRow(
              currency: entry.key,
              amount: balanceSelector(entry.value).balance,
              usdValue: balanceSelector(entry.value).usdValue,
            ),
        ],
      ),
    );
  }
}

/* -------------------------------------------------------------------------- */
/*                       CREDIT AGENT BALANCE ROW                             */
/* -------------------------------------------------------------------------- */

class _CreditAgentBalanceRow extends StatelessWidget {
  const _CreditAgentBalanceRow({
    required this.currency,
    required this.amount,
    required this.usdValue,
  });

  final String currency;
  final double amount;
  final double usdValue;

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    final colorScheme = context.colorScheme;

    return Padding(
      padding: EdgeInsets.only(bottom: spacing.sm),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(currency.toUpperCase(), style: AppTextStyles.small(context)),

              Text(
                NumberFormatService.formatAmount(amount, currency: currency),
                style: AppTextStyles.smallNumber(context),
              ),
            ],
          ),

          if (currency.toLowerCase() != 'usd')
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Text(
                  '≈ ${NumberFormatService.formatAmount(usdValue, currency: 'usd')}',
                  style: AppTextStyles.tinyNumber(
                    context,
                  ).copyWith(color: colorScheme.onSurfaceVariant),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

// import 'package:flutter/material.dart';
// import 'package:flutter_riverpod/flutter_riverpod.dart';
// import 'package:go_router/go_router.dart';
// import 'package:ngoda/core/providers/hive_service_provider.dart';
// import 'package:ngoda/data_models/currency/currency_balance.dart';
// import 'package:ngoda/data_models/merchant/credit_agent_currency_balance.dart';
// import 'package:ngoda/data_models/wallet/wallet.dart';
// import 'package:ngoda/services/hive_service.dart';
// import 'package:ngoda/services/number_format_service.dart';
// import 'package:ngoda/ui/enums/enums.dart';
// import 'package:ngoda/ui/extensions/app_size.dart';
// import 'package:ngoda/ui/extensions/theme_extension.dart';
// import 'package:ngoda/ui/functions/compute_net_position.dart';
// import 'package:ngoda/ui/functions/get_user_home_screen_quick_links.dart';
// import 'package:ngoda/ui/functions/is_jwt_expired.dart';
// import 'package:ngoda/ui/screens/auth/providers/auth_provider.dart';
// import 'package:ngoda/ui/screens/home/vendor_dashboard_screen.dart';
// import 'package:ngoda/ui/screens/merchant/provider/merchant_dashboard_provider.dart';
// import 'package:ngoda/ui/shared/app_text_styles.dart';
// import 'package:ngoda/ui/shared/theme_provider.dart';
// import 'package:ngoda/ui/widgets/app_error_state.dart';
// import 'package:ngoda/ui/widgets/app_loader.dart';
// import 'package:ngoda/ui/widgets/bottom_nav.dart';
// import 'package:ngoda/ui/widgets/dashboard_quick_actions.dart';
// import 'package:ngoda/ui/widgets/fiat_card.dart';
// import 'package:ngoda/ui/widgets/net_position_card.dart';

// class MerchantDashboardScreen extends ConsumerWidget {
//   const MerchantDashboardScreen({super.key});

//   @override
//   Widget build(BuildContext context, WidgetRef ref) {
//     final spacing = context.spacing;
//     final iconSize = context.iconSize;
//     final colorScheme = context.colorScheme;

//     final nfcSupported =
//         ref
//             .read(hiveServiceProvider)
//             .getItem<bool>(HiveBoxName.nfcSupport, 'nfcSupported')
//             .result ??
//         false;

//     final asyncData = ref.watch(merchantDashboardProvider);

//     return asyncData.when(
//       loading: () => const AppLoader(
//         message: 'Loading merchant dashboard',
//         fullScreen: true,
//       ),
//       error: (error, _) {
//         if (isJwtExpired(error)) {
//           return _SessionExpiredState(ref: ref);
//         }

//         return Scaffold(body: AppErrorState(message: error.toString()));
//       },
//       data: (response) {
//         if (response.error != null) {
//           if (isJwtExpired(response.error!)) {
//             return _SessionExpiredState(ref: ref);
//           }

//           return Scaffold(body: AppErrorState(message: response.error!));
//         }

//         final dashboard = response.result;

//         if (dashboard == null) {
//           return const Scaffold(
//             body: AppErrorState(
//               title: 'Merchant Dashboard',
//               message: 'Merchant dashboard is not available.',
//             ),
//           );
//         }

//         /*
//          * Credit-agent capability comes from the Merchant dashboard.
//          * It applies specifically to Merchant.
//          */
//         final quickLinks = getUserHomeScreenQuickLinks(
//           context: context,
//           role: UserRole.merchant,
//           iconSize: iconSize.medium,
//           primary: colorScheme.primary,
//           nfcSupported: nfcSupported,
//           isCreditAgent: dashboard.isCreditAgent,
//         );

//         final netPosition = computeMerchantNetPosition(dashboard);

//         return Scaffold(
//           bottomNavigationBar: const BottomNav(currentIndex: 0),
//           body: SafeArea(
//             child: RefreshIndicator(
//               onRefresh: () async {
//                 ref.invalidate(merchantDashboardProvider);

//                 await ref.read(merchantDashboardProvider.future);
//               },
//               child: CustomScrollView(
//                 physics: const AlwaysScrollableScrollPhysics(),
//                 slivers: [
//                   SliverPadding(
//                     padding: EdgeInsets.fromLTRB(
//                       spacing.padding,
//                       spacing.md,
//                       spacing.padding,
//                       spacing.padding,
//                     ),
//                     sliver: SliverList(
//                       delegate: SliverChildListDelegate([
//                         /*
//                            * Header
//                            */
//                         Row(
//                           mainAxisAlignment: MainAxisAlignment.spaceBetween,
//                           children: [
//                             Text(
//                               'Welcome Back',
//                               style: AppTextStyles.large(
//                                 context,
//                               ).copyWith(fontWeight: FontWeight.w700),
//                             ),
//                             Consumer(
//                               builder: (context, ref, _) {
//                                 final mode = ref.watch(themeModeProvider);

//                                 return IconButton(
//                                   iconSize: iconSize.medium,
//                                   onPressed: () {
//                                     ref
//                                         .read(themeModeProvider.notifier)
//                                         .toggle();
//                                   },
//                                   icon: Icon(
//                                     mode == ThemeMode.dark
//                                         ? Icons.light_mode
//                                         : Icons.dark_mode,
//                                   ),
//                                 );
//                               },
//                             ),
//                           ],
//                         ),

//                         SizedBox(height: spacing.xs),

//                         Text(
//                           'Overview of your financial position',
//                           style: AppTextStyles.small(
//                             context,
//                           ).copyWith(color: colorScheme.onSurfaceVariant),
//                         ),

//                         SizedBox(height: spacing.md),

//                         NetPositionCard(amount: netPosition),

//                         /*
//                            * Shared dashboard quick actions.
//                            * Merchant role determines the actions.
//                            */
//                         if (quickLinks.isNotEmpty) ...[
//                           SizedBox(height: spacing.md),
//                           DashboardQuickActions(quickLinks: quickLinks),
//                         ],

//                         SizedBox(height: spacing.lg),

//                         /*
//                            * MERCHANT WALLET
//                            *
//                            * Funds received from customer payments.
//                            */
//                         _WalletSection(
//                           title: 'Merchant Wallet',
//                           subtitle: 'Funds received from customer payments',
//                           wallet: dashboard.merchantWallet,
//                         ),

//                         SizedBox(height: spacing.md),

//                         /*
//                            * Payments received today.
//                            */
//                         DailyPaymentSummaryCard(
//                           summary: dashboard.dailySummary,
//                         ),

//                         SizedBox(height: spacing.md),

//                         /*
//                            * AGENT WALLET
//                            *
//                            * Merchant can also perform agent operations.
//                            */
//                         _WalletSection(
//                           title: 'Agent Wallet',
//                           subtitle:
//                               'Float used for customer cash in and cash out',
//                           wallet: dashboard.agentWallet,
//                         ),

//                         /*
//                            * CREDIT AGENT
//                            *
//                            * Credit-agent capability applies specifically
//                            * to Merchant.
//                            */
//                         if (dashboard.isCreditAgent) ...[
//                           SizedBox(height: spacing.md),
//                           CreditWalletSection(
//                             title: 'Cash Owed',
//                             subtitle: 'Cash collected and owed to treasury',
//                             wallet: dashboard.creditAgent,
//                             balanceSelector: (balance) => balance.cashOwed,
//                           ),
//                           SizedBox(height: spacing.md),
//                           CreditWalletSection(
//                             title: 'Receivable Balance',
//                             subtitle: 'Outstanding amount receivable',
//                             wallet: dashboard.creditAgent,
//                             balanceSelector: (balance) =>
//                                 balance.receivableBalance,
//                           ),
//                         ],

//                         SizedBox(height: spacing.md),

//                         /*
//                            * Agent-operation activity.
//                            */
//                         DailySummaryCard(summary: dashboard.dailySummary),
//                       ]),
//                     ),
//                   ),
//                 ],
//               ),
//             ),
//           ),
//         );
//       },
//     );
//   }
// }

// /* -------------------------------------------------------------------------- */
// /*                           SESSION EXPIRED                                  */
// /* -------------------------------------------------------------------------- */

// class _SessionExpiredState extends StatelessWidget {
//   const _SessionExpiredState({required this.ref});

//   final WidgetRef ref;

//   @override
//   Widget build(BuildContext context) {
//     return Scaffold(
//       body: AppErrorState(
//         title: 'Session Expired',
//         message: 'Please login again to continue.',
//         buttonText: 'Logout',
//         onAction: () async {
//           await ref.read(authProvider.notifier).logout('Session Expired');

//           if (!context.mounted) {
//             return;
//           }

//           context.go('/login');
//         },
//       ),
//     );
//   }
// }

// /* -------------------------------------------------------------------------- */
// /*                              WALLET SECTION                                */
// /* -------------------------------------------------------------------------- */

// class _WalletSection extends StatelessWidget {
//   const _WalletSection({
//     required this.title,
//     required this.subtitle,
//     required this.wallet,
//   });

//   final String title;
//   final String subtitle;
//   final Wallet wallet;

//   @override
//   Widget build(BuildContext context) {
//     final spacing = context.spacing;
//     final colorScheme = context.colorScheme;

//     return Column(
//       crossAxisAlignment: CrossAxisAlignment.start,
//       children: [
//         Text(
//           title,
//           style: AppTextStyles.small(
//             context,
//           ).copyWith(fontWeight: FontWeight.w700),
//         ),
//         SizedBox(height: spacing.xs),
//         Text(
//           subtitle,
//           style: AppTextStyles.tiny(
//             context,
//           ).copyWith(color: colorScheme.onSurfaceVariant),
//         ),
//         SizedBox(height: spacing.sm),
//         FiatCard(wallet: wallet),
//       ],
//     );
//   }
// }

// /* -------------------------------------------------------------------------- */
// /*                          CREDIT AGENT WALLET                               */
// /* -------------------------------------------------------------------------- */

// typedef CreditAgentBalanceSelector =
//     CurrencyBalance Function(CreditAgentCurrencyBalance balance);

// class CreditWalletSection extends StatelessWidget {
//   const CreditWalletSection({
//     super.key,
//     required this.title,
//     required this.subtitle,
//     required this.wallet,
//     required this.balanceSelector,
//   });

//   final String title;
//   final String subtitle;
//   final CreditAgentWallet wallet;
//   final CreditAgentBalanceSelector balanceSelector;

//   @override
//   Widget build(BuildContext context) {
//     final spacing = context.spacing;
//     final colorScheme = context.colorScheme;

//     return Column(
//       crossAxisAlignment: CrossAxisAlignment.start,
//       children: [
//         Text(
//           title,
//           style: AppTextStyles.small(
//             context,
//           ).copyWith(fontWeight: FontWeight.w700),
//         ),
//         SizedBox(height: spacing.xs),
//         Text(
//           subtitle,
//           style: AppTextStyles.tiny(
//             context,
//           ).copyWith(color: colorScheme.onSurfaceVariant),
//         ),
//         SizedBox(height: spacing.sm),
//         CreditAgentBalanceCard(
//           wallet: wallet,
//           balanceSelector: balanceSelector,
//         ),
//       ],
//     );
//   }
// }

// /* -------------------------------------------------------------------------- */
// /*                         CREDIT AGENT BALANCE CARD                          */
// /* -------------------------------------------------------------------------- */

// class CreditAgentBalanceCard extends StatelessWidget {
//   const CreditAgentBalanceCard({
//     super.key,
//     required this.wallet,
//     required this.balanceSelector,
//   });

//   final CreditAgentWallet wallet;
//   final CreditAgentBalanceSelector balanceSelector;

//   @override
//   Widget build(BuildContext context) {
//     final spacing = context.spacing;
//     final radius = context.radius;
//     final colorScheme = context.colorScheme;

//     final fiatEntries = wallet.currencyEntries
//         .where((entry) => entry.key.toLowerCase() != 'gold')
//         .toList();

//     final totalUsd = fiatEntries.fold<double>(
//       0,
//       (sum, entry) => sum + balanceSelector(entry.value).usdValue,
//     );

//     return Container(
//       padding: EdgeInsets.all(spacing.sm),
//       decoration: BoxDecoration(
//         color: colorScheme.surfaceContainer,
//         borderRadius: BorderRadius.circular(radius.borderRadius),
//         border: Border.all(color: colorScheme.primary.withValues(alpha: 0.25)),
//       ),
//       child: Column(
//         crossAxisAlignment: CrossAxisAlignment.start,
//         children: [
//           Text(
//             'Total Balance',
//             style: AppTextStyles.small(
//               context,
//             ).copyWith(color: colorScheme.onSurfaceVariant),
//           ),

//           SizedBox(height: spacing.xs),

//           Text(
//             NumberFormatService.formatAmount(totalUsd, currency: 'usd'),
//             style: AppTextStyles.largeNumber(
//               context,
//             ).copyWith(fontWeight: FontWeight.w700, color: colorScheme.primary),
//           ),

//           const Divider(),

//           Text(
//             'Breakdown',
//             style: AppTextStyles.small(
//               context,
//             ).copyWith(color: colorScheme.onSurfaceVariant),
//           ),

//           SizedBox(height: spacing.sm),

//           for (final entry in fiatEntries)
//             _CreditAgentBalanceRow(
//               currency: entry.key,
//               amount: balanceSelector(entry.value).balance,
//               usdValue: balanceSelector(entry.value).usdValue,
//             ),
//         ],
//       ),
//     );
//   }
// }

// /* -------------------------------------------------------------------------- */
// /*                          CREDIT AGENT BALANCE ROW                          */
// /* -------------------------------------------------------------------------- */

// class _CreditAgentBalanceRow extends StatelessWidget {
//   const _CreditAgentBalanceRow({
//     required this.currency,
//     required this.amount,
//     required this.usdValue,
//   });

//   final String currency;
//   final double amount;
//   final double usdValue;

//   @override
//   Widget build(BuildContext context) {
//     final spacing = context.spacing;
//     final colorScheme = context.colorScheme;

//     return Padding(
//       padding: EdgeInsets.only(bottom: spacing.sm),
//       child: Column(
//         children: [
//           Row(
//             mainAxisAlignment: MainAxisAlignment.spaceBetween,
//             children: [
//               Text(currency.toUpperCase(), style: AppTextStyles.small(context)),
//               Text(
//                 NumberFormatService.formatAmount(amount, currency: currency),
//                 style: AppTextStyles.smallNumber(context),
//               ),
//             ],
//           ),

//           if (currency.toLowerCase() != 'usd')
//             Row(
//               mainAxisAlignment: MainAxisAlignment.end,
//               children: [
//                 Text(
//                   '≈ ${NumberFormatService.formatAmount(usdValue, currency: 'usd')}',
//                   style: AppTextStyles.tinyNumber(
//                     context,
//                   ).copyWith(color: colorScheme.onSurfaceVariant),
//                 ),
//               ],
//             ),
//         ],
//       ),
//     );
//   }
// }
