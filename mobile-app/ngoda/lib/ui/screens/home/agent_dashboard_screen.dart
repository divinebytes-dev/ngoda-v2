import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:ngoda/core/providers/hive_service_provider.dart';
import 'package:ngoda/services/hive_service.dart';
import 'package:ngoda/ui/enums/enums.dart';
import 'package:ngoda/ui/extensions/app_size.dart';
import 'package:ngoda/ui/extensions/theme_extension.dart';
import 'package:ngoda/ui/functions/compute_net_position.dart';
import 'package:ngoda/ui/functions/get_user_home_screen_quick_links.dart';
import 'package:ngoda/ui/functions/is_jwt_expired.dart';
import 'package:ngoda/ui/screens/agent/providers/agent_dashboard_provider.dart';
import 'package:ngoda/ui/screens/auth/providers/auth_provider.dart';
import 'package:ngoda/ui/screens/home/vendor_dashboard_screen.dart';
import 'package:ngoda/ui/shared/app_text_styles.dart';
import 'package:ngoda/ui/shared/theme_provider.dart';
import 'package:ngoda/ui/widgets/app_error_state.dart';
import 'package:ngoda/ui/widgets/app_loader.dart';
import 'package:ngoda/ui/widgets/bottom_nav.dart';
import 'package:ngoda/ui/widgets/dashboard_quick_actions.dart';
import 'package:ngoda/ui/widgets/fiat_card.dart';
import 'package:ngoda/ui/widgets/net_position_card.dart';

enum _AgentWalletType { personal, agent }

class AgentDashboardScreen extends ConsumerStatefulWidget {
  const AgentDashboardScreen({super.key});

  @override
  ConsumerState<AgentDashboardScreen> createState() =>
      _AgentDashboardScreenState();
}

class _AgentDashboardScreenState extends ConsumerState<AgentDashboardScreen> {
  _AgentWalletType _selectedWallet = _AgentWalletType.personal;

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

    final quickLinks = getUserHomeScreenQuickLinks(
      context: context,
      role: UserRole.agent,
      iconSize: iconSize.medium,
      primary: colorScheme.primary,
      nfcSupported: nfcSupported,
    );

    final asyncData = ref.watch(agentDashboardProvider);

    return asyncData.when(
      loading: () =>
          const AppLoader(message: 'Loading agent dashboard', fullScreen: true),
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
              title: 'Agent Dashboard',
              message: 'Agent dashboard is not available.',
            ),
          );
        }

        final netPosition = computeAgentNetPosition(dashboard);

        return Scaffold(
          bottomNavigationBar: const BottomNav(currentIndex: 0),
          body: SafeArea(
            child: RefreshIndicator(
              onRefresh: () async {
                ref.invalidate(agentDashboardProvider);

                await ref.read(agentDashboardProvider.future);
              },
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: EdgeInsets.fromLTRB(
                  spacing.md,
                  spacing.md,
                  spacing.md,
                  spacing.lg,
                ),
                children: [
                  _DashboardHeader(
                    themeMode: ref.watch(themeModeProvider),
                    onThemeChanged: () {
                      ref.read(themeModeProvider.notifier).toggle();
                    },
                  ),

                  SizedBox(height: spacing.lg),

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
      case _AgentWalletType.personal:
        return Column(
          key: const ValueKey(_AgentWalletType.personal),
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const _WalletHeading(
              title: 'Personal Wallet',
              description: 'Your personal wallet balances.',
            ),

            SizedBox(height: spacing.sm),

            FiatCard(wallet: dashboard.customerWallet),
          ],
        );

      case _AgentWalletType.agent:
        return Column(
          key: const ValueKey(_AgentWalletType.agent),
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const _WalletHeading(
              title: 'Agent Wallet',
              description: 'Float used for customer cash in and cash out.',
            ),

            SizedBox(height: spacing.sm),

            FiatCard(wallet: dashboard.agentWallet),

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
                'Welcome back',
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

  final _AgentWalletType selectedWallet;

  final ValueChanged<_AgentWalletType> onSelected;

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
              title: 'Personal',
              selected: selectedWallet == _AgentWalletType.personal,
              onTap: () {
                onSelected(_AgentWalletType.personal);
              },
            ),
          ),

          SizedBox(width: spacing.xs),

          Expanded(
            child: _WalletTab(
              title: 'Agent',
              selected: selectedWallet == _AgentWalletType.agent,
              onTap: () {
                onSelected(_AgentWalletType.agent);
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

/* -------------------------------------------------------------------------- */
/*                            SESSION EXPIRED                                 */
/* -------------------------------------------------------------------------- */

class _SessionExpiredState extends StatelessWidget {
  final WidgetRef ref;

  const _SessionExpiredState({required this.ref});

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

// import 'package:flutter/material.dart';
// import 'package:flutter_riverpod/flutter_riverpod.dart';
// import 'package:go_router/go_router.dart';
// import 'package:ngoda/core/providers/hive_service_provider.dart';
// import 'package:ngoda/data_models/wallet/wallet.dart';
// import 'package:ngoda/services/hive_service.dart';
// import 'package:ngoda/ui/enums/enums.dart';
// import 'package:ngoda/ui/extensions/app_size.dart';
// import 'package:ngoda/ui/extensions/theme_extension.dart';
// import 'package:ngoda/ui/functions/compute_net_position.dart';
// import 'package:ngoda/ui/functions/get_user_home_screen_quick_links.dart';
// import 'package:ngoda/ui/functions/is_jwt_expired.dart';
// import 'package:ngoda/ui/screens/agent/providers/agent_dashboard_provider.dart';
// import 'package:ngoda/ui/screens/auth/providers/auth_provider.dart';
// import 'package:ngoda/ui/screens/home/vendor_dashboard_screen.dart';
// import 'package:ngoda/ui/shared/app_text_styles.dart';
// import 'package:ngoda/ui/shared/theme_provider.dart';
// import 'package:ngoda/ui/widgets/app_error_state.dart';
// import 'package:ngoda/ui/widgets/app_loader.dart';
// import 'package:ngoda/ui/widgets/bottom_nav.dart';
// import 'package:ngoda/ui/widgets/dashboard_quick_actions.dart';
// import 'package:ngoda/ui/widgets/fiat_card.dart';
// import 'package:ngoda/ui/widgets/net_position_card.dart';

// class AgentDashboardScreen extends ConsumerWidget {
//   const AgentDashboardScreen({super.key});

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

//     final quickLinks = getUserHomeScreenQuickLinks(
//       context: context,
//       role: UserRole.agent,
//       iconSize: iconSize.medium,
//       primary: colorScheme.primary,
//       nfcSupported: nfcSupported,
//     );

//     final asyncData = ref.watch(agentDashboardProvider);

//     return asyncData.when(
//       loading: () =>
//           const AppLoader(message: 'Loading agent dashboard', fullScreen: true),
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
//               title: 'Agent Dashboard',
//               message: 'Agent dashboard is not available.',
//             ),
//           );
//         }

//         final netPosition = computeAgentNetPosition(dashboard);

//         return Scaffold(
//           bottomNavigationBar: const BottomNav(currentIndex: 0),
//           body: SafeArea(
//             child: Column(
//               children: [
//                 Padding(
//                   padding: EdgeInsets.fromLTRB(
//                     spacing.padding,
//                     spacing.sm,
//                     spacing.padding,
//                     spacing.sm,
//                   ),
//                   child: Column(
//                     children: [
//                       SizedBox(height: spacing.md),

//                       /*
//                        * Header
//                        */
//                       Row(
//                         mainAxisAlignment: MainAxisAlignment.spaceBetween,
//                         children: [
//                           Text(
//                             'Welcome back',
//                             style: AppTextStyles.large(
//                               context,
//                             ).copyWith(fontWeight: FontWeight.w700),
//                           ),
//                           Consumer(
//                             builder: (context, ref, _) {
//                               final mode = ref.watch(themeModeProvider);

//                               return IconButton(
//                                 iconSize: iconSize.medium,
//                                 onPressed: () {
//                                   ref.read(themeModeProvider.notifier).toggle();
//                                 },
//                                 icon: Icon(
//                                   mode == ThemeMode.dark
//                                       ? Icons.light_mode
//                                       : Icons.dark_mode,
//                                 ),
//                               );
//                             },
//                           ),
//                         ],
//                       ),

//                       SizedBox(height: spacing.xs),

//                       Text(
//                         'Overview of your financial position',
//                         textAlign: TextAlign.center,
//                         style: AppTextStyles.small(
//                           context,
//                         ).copyWith(color: colorScheme.onSurfaceVariant),
//                       ),

//                       SizedBox(height: spacing.md),

//                       /*
//                        * Agent financial position
//                        */
//                       NetPositionCard(amount: netPosition),

//                       SizedBox(height: spacing.md),

//                       /*
//                        * Agent quick actions
//                        */
//                       // Row(
//                       //   children: [
//                       //     SizedBox(width: spacing.xs),
//                       //     Expanded(child: quickLinks.first),
//                       //     SizedBox(width: spacing.md),
//                       //     Expanded(child: quickLinks.last),
//                       //     SizedBox(width: spacing.xs),
//                       //   ],
//                       // ),
//                       if (quickLinks.isNotEmpty) ...[
//                         SizedBox(height: spacing.md),

//                         DashboardQuickActions(quickLinks: quickLinks),
//                       ],
//                       SizedBox(height: spacing.md),
//                     ],
//                   ),
//                 ),

//                 Expanded(
//                   child: RefreshIndicator(
//                     onRefresh: () async {
//                       ref.invalidate(agentDashboardProvider);

//                       await ref.read(agentDashboardProvider.future);
//                     },
//                     child: SingleChildScrollView(
//                       physics: const AlwaysScrollableScrollPhysics(),
//                       padding: EdgeInsets.fromLTRB(
//                         spacing.padding,
//                         spacing.sm,
//                         spacing.padding,
//                         spacing.padding,
//                       ),
//                       child: Column(
//                         children: [
//                           /*
//                            * Agent operational wallet / float.
//                            */
//                           _WalletSection(
//                             title: 'Agent Wallet',
//                             subtitle:
//                                 'Float used for customer cash in and cash out',
//                             wallet: dashboard.agentWallet,
//                           ),

//                           SizedBox(height: spacing.md),

//                           /*
//                            * Agent activity for today.
//                            */
//                           DailySummaryCard(summary: dashboard.dailySummary),

//                           SizedBox(height: spacing.md),

//                           /*
//                            * Agent's own personal wallet.
//                            */
//                           _WalletSection(
//                             title: 'Personal Wallet',
//                             subtitle: 'Personal funds',
//                             wallet: dashboard.customerWallet,
//                           ),
//                         ],
//                       ),
//                     ),
//                   ),
//                 ),
//               ],
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
//   final WidgetRef ref;

//   const _SessionExpiredState({required this.ref});

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
//   final String title;
//   final String subtitle;
//   final Wallet wallet;

//   const _WalletSection({
//     required this.title,
//     required this.subtitle,
//     required this.wallet,
//   });

//   @override
//   Widget build(BuildContext context) {
//     final spacing = context.spacing;
//     final colorScheme = context.colorScheme;

//     return Column(
//       crossAxisAlignment: CrossAxisAlignment.start,
//       children: [
//         Center(
//           child: Text(
//             title,
//             style: AppTextStyles.small(
//               context,
//             ).copyWith(fontWeight: FontWeight.w700),
//           ),
//         ),

//         SizedBox(height: spacing.xs),

//         Center(
//           child: Text(
//             subtitle,
//             textAlign: TextAlign.center,
//             style: AppTextStyles.tiny(
//               context,
//             ).copyWith(color: colorScheme.onSurfaceVariant),
//           ),
//         ),

//         SizedBox(height: spacing.sm),

//         FiatCard(wallet: wallet),
//       ],
//     );
//   }
// }
