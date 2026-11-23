import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:ngoda/ui/extensions/app_size.dart';
import 'package:ngoda/ui/extensions/theme_extension.dart';
import 'package:ngoda/ui/functions/is_jwt_expired.dart';
import 'package:ngoda/ui/screens/auth/providers/auth_provider.dart';
import 'package:ngoda/ui/screens/reserve-bank/providers/reserve_bank_dashboard_povider.dart';
import 'package:ngoda/ui/shared/app_text_styles.dart';
import 'package:ngoda/ui/shared/theme_provider.dart';
import 'package:ngoda/ui/widgets/app_error_state.dart';
import 'package:ngoda/ui/widgets/app_loader.dart';
import 'package:ngoda/ui/widgets/bottom_nav.dart';
import 'package:ngoda/ui/widgets/net_position_card.dart';

class ReserveBankDashboardScreen extends ConsumerWidget {
  const ReserveBankDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final spacing = context.spacing;
    final asyncData = ref.watch(reserveBankDashboardProvider);

    return asyncData.when(
      loading: () => const AppLoader(
        message: 'Loading Reserve Bank dashboard',
        fullScreen: true,
      ),
      error: (error, _) {
        if (isJwtExpired(error)) {
          return _SessionExpiredState(ref: ref);
        }

        return Scaffold(body: AppErrorState(message: error.toString()));
      },
      data: (response) {
        final error = response.error;
        if (error != null) {
          if (isJwtExpired(error)) {
            return _SessionExpiredState(ref: ref);
          }

          return Scaffold(body: AppErrorState(message: error));
        }

        final dashboard = response.result;
        if (dashboard == null) {
          return const Scaffold(
            body: AppErrorState(
              title: 'Reserve Bank Dashboard',
              message: 'Reserve Bank dashboard is not available.',
            ),
          );
        }

        final netPosition = double.tryParse(dashboard.totalUsd ?? '');

        return Scaffold(
          bottomNavigationBar: const BottomNav(currentIndex: 0),
          body: SafeArea(
            child: RefreshIndicator(
              onRefresh: () async {
                ref.invalidate(reserveBankDashboardProvider);
                await ref.read(reserveBankDashboardProvider.future);
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
                  if (netPosition != null && netPosition.isFinite)
                    NetPositionCard(amount: netPosition)
                  else
                    Text(
                      'Net position unavailable',
                      style: AppTextStyles.small(context),
                    ),
                  SizedBox(height: spacing.lg),
                  Text(
                    'Breakdown by currency',
                    style: AppTextStyles.small(
                      context,
                    ).copyWith(fontWeight: FontWeight.w700),
                  ),
                  if (dashboard.currencyBreakdown.isEmpty)
                    Padding(
                      padding: EdgeInsets.only(top: spacing.sm),
                      child: Text(
                        'No tax recorded',
                        style: AppTextStyles.small(context),
                      ),
                    ),
                  for (final item in dashboard.currencyBreakdown)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text('${item.currency.toUpperCase()} ${item.tax}'),
                      trailing: Text(
                        item.usdValue == null
                            ? 'USD value unavailable'
                            : 'USD ${item.usdValue}',
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
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
                'Reserve Bank dashboard',
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
