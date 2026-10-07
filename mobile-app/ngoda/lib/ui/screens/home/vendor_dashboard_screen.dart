import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:ngoda/core/providers/hive_service_provider.dart';
import 'package:ngoda/data_models/transaction/daily_transaction_summary.dart';
import 'package:ngoda/services/hive_service.dart';
import 'package:ngoda/services/number_format_service.dart';
import 'package:ngoda/ui/enums/enums.dart';
import 'package:ngoda/ui/extensions/app_size.dart';
import 'package:ngoda/ui/extensions/theme_extension.dart';
import 'package:ngoda/ui/functions/compute_net_position.dart';
import 'package:ngoda/ui/functions/get_user_home_screen_quick_links.dart';
import 'package:ngoda/ui/functions/is_jwt_expired.dart';
import 'package:ngoda/ui/screens/auth/providers/auth_provider.dart';
import 'package:ngoda/ui/screens/vendor/provider/vendor_dashboard_provider.dart';
import 'package:ngoda/ui/shared/app_text_styles.dart';
import 'package:ngoda/ui/shared/theme_provider.dart';
import 'package:ngoda/ui/widgets/app_error_state.dart';
import 'package:ngoda/ui/widgets/app_loader.dart';
import 'package:ngoda/ui/widgets/bottom_nav.dart';
import 'package:ngoda/ui/widgets/dashboard_quick_actions.dart';
import 'package:ngoda/ui/widgets/fiat_card.dart';
import 'package:ngoda/ui/widgets/net_position_card.dart';

enum _VendorWalletType { personal, agent, merchant }

class VendorDashboardScreen extends ConsumerStatefulWidget {
  const VendorDashboardScreen({super.key});

  @override
  ConsumerState<VendorDashboardScreen> createState() =>
      _VendorDashboardScreenState();
}

class _VendorDashboardScreenState extends ConsumerState<VendorDashboardScreen> {
  _VendorWalletType _selectedWallet = _VendorWalletType.personal;

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    final iconSize = context.iconSize;
    final colorScheme = context.colorScheme;

    final asyncData = ref.watch(vendorDashboardProvider);

    return asyncData.when(
      loading: () =>
          const AppLoader(message: 'Loading dashboard', fullScreen: true),
      error: (error, _) {
        return _buildErrorState(context, error);
      },
      data: (response) {
        if (response.error != null) {
          return _buildErrorState(context, response.error!);
        }

        final dashboard = response.result;

        if (dashboard == null) {
          return const Scaffold(
            body: AppErrorState(message: 'Dashboard data is unavailable.'),
          );
        }

        /*
         * Vendor net position continues to use the
         * existing Vendor dashboard calculation.
         */
        final netPosition = computeVendorNetPosition(dashboard);

        /*
         * NFC support is device state and is not part
         * of the Vendor dashboard response.
         */
        final nfcSupported =
            ref
                .read(hiveServiceProvider)
                .getItem<bool>(HiveBoxName.nfcSupport, 'nfcSupported')
                .result ??
            false;

        final quickLinks = getUserHomeScreenQuickLinks(
          context: context,
          role: UserRole.vendor,
          iconSize: iconSize.medium,
          primary: colorScheme.primary,
          nfcSupported: nfcSupported,
        );

        return Scaffold(
          bottomNavigationBar: const BottomNav(currentIndex: 0),
          body: SafeArea(
            child: RefreshIndicator(
              onRefresh: () async {
                ref.invalidate(vendorDashboardProvider);

                await ref.read(vendorDashboardProvider.future);
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
                    onThemeChanged: () {
                      ref.read(themeModeProvider.notifier).toggle();
                    },
                    themeMode: ref.watch(themeModeProvider),
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
      case _VendorWalletType.personal:
        return Column(
          key: const ValueKey(_VendorWalletType.personal),
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

      case _VendorWalletType.agent:
        return Column(
          key: const ValueKey(_VendorWalletType.agent),
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const _WalletHeading(
              title: 'Agent Wallet',
              description: 'Your agent balance and today\'s cash activity.',
            ),

            SizedBox(height: spacing.sm),

            FiatCard(wallet: dashboard.agentWallet),

            SizedBox(height: spacing.md),

            DailySummaryCard(summary: dashboard.dailySummary),
          ],
        );

      case _VendorWalletType.merchant:
        return Column(
          key: const ValueKey(_VendorWalletType.merchant),
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const _WalletHeading(
              title: 'Merchant Wallet',
              description:
                  'Your merchant balance and today\'s payment activity.',
            ),

            SizedBox(height: spacing.sm),

            FiatCard(wallet: dashboard.merchantWallet),

            SizedBox(height: spacing.md),

            DailyPaymentSummaryCard(summary: dashboard.dailySummary),
          ],
        );
    }
  }

  Widget _buildErrorState(BuildContext context, Object error) {
    if (!isJwtExpired(error)) {
      return Scaffold(
        body: AppErrorState(
          message: error.toString(),
          buttonText: 'Retry',
          onAction: () {
            ref.invalidate(vendorDashboardProvider);
          },
        ),
      );
    }

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
                'Your financial position',
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
          onPressed: onThemeChanged,
          icon: Icon(
            themeMode == ThemeMode.dark
                ? Icons.light_mode_outlined
                : Icons.dark_mode_outlined,
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

  final _VendorWalletType selectedWallet;

  final ValueChanged<_VendorWalletType> onSelected;

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
              selected: selectedWallet == _VendorWalletType.personal,
              onTap: () {
                onSelected(_VendorWalletType.personal);
              },
            ),
          ),

          SizedBox(width: spacing.xs),

          Expanded(
            child: _WalletTab(
              title: 'Agent',
              selected: selectedWallet == _VendorWalletType.agent,
              onTap: () {
                onSelected(_VendorWalletType.agent);
              },
            ),
          ),

          SizedBox(width: spacing.xs),

          Expanded(
            child: _WalletTab(
              title: 'Merchant',
              selected: selectedWallet == _VendorWalletType.merchant,
              onTap: () {
                onSelected(_VendorWalletType.merchant);
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

/*
 * Merchant payment activity.
 *
 * Vendor payment activity uses the `payments`
 * portion of DailyTransactionSummary.
 */
class DailyPaymentSummaryCard extends StatefulWidget {
  const DailyPaymentSummaryCard({super.key, required this.summary});

  final DailyTransactionSummary summary;

  @override
  State<DailyPaymentSummaryCard> createState() =>
      _DailyPaymentSummaryCardState();
}

class _DailyPaymentSummaryCardState extends State<DailyPaymentSummaryCard> {
  String? _selectedCurrency;

  List<String> get _currencies {
    final currencies = {
      ...widget.summary.payments.keys,
      ...widget.summary.paymentCount.keys,
    }.toList()..sort();

    return currencies;
  }

  @override
  void initState() {
    super.initState();

    final currencies = _currencies;

    if (currencies.isNotEmpty) {
      _selectedCurrency = currencies.first;
    }
  }

  @override
  void didUpdateWidget(covariant DailyPaymentSummaryCard oldWidget) {
    super.didUpdateWidget(oldWidget);

    final currencies = _currencies;

    if (currencies.isEmpty) {
      _selectedCurrency = null;
      return;
    }

    if (_selectedCurrency == null || !currencies.contains(_selectedCurrency)) {
      _selectedCurrency = currencies.first;
    }
  }

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;

    final currencies = _currencies;

    if (currencies.isEmpty) {
      return const SizedBox.shrink();
    }

    final selectedCurrency = _selectedCurrency ?? currencies.first;

    final payment = widget.summary.payment(selectedCurrency);

    final paymentCount = widget.summary.paymentTransactions(selectedCurrency);

    return _SummaryCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _CurrencySelector(
            currencies: currencies,
            selectedCurrency: selectedCurrency,
            onSelected: (currency) {
              setState(() {
                _selectedCurrency = currency;
              });
            },
          ),

          SizedBox(height: spacing.md),

          _SummaryBlock(
            title: 'Incoming Payments',
            amount: payment?.balance ?? 0,
            usdValue: payment?.usdValue ?? 0,
            count: paymentCount,
            color: const Color(0xFF16A34A),
            currency: selectedCurrency.toUpperCase(),
          ),
        ],
      ),
    );
  }
}

/*
 * Agent cash activity.
 *
 * Deposits and withdrawals remain separate
 * from merchant payment activity.
 */
class DailySummaryCard extends StatefulWidget {
  const DailySummaryCard({super.key, required this.summary});

  final DailyTransactionSummary summary;

  @override
  State<DailySummaryCard> createState() => _DailySummaryCardState();
}

class _DailySummaryCardState extends State<DailySummaryCard> {
  String? _selectedCurrency;

  List<String> get _currencies {
    final currencies = {
      ...widget.summary.deposits.keys,
      ...widget.summary.withdrawals.keys,
      ...widget.summary.depositCount.keys,
      ...widget.summary.withdrawalCount.keys,
    }.toList()..sort();

    return currencies;
  }

  @override
  void initState() {
    super.initState();

    final currencies = _currencies;

    if (currencies.isNotEmpty) {
      _selectedCurrency = currencies.first;
    }
  }

  @override
  void didUpdateWidget(covariant DailySummaryCard oldWidget) {
    super.didUpdateWidget(oldWidget);

    final currencies = _currencies;

    if (currencies.isEmpty) {
      _selectedCurrency = null;
      return;
    }

    if (_selectedCurrency == null || !currencies.contains(_selectedCurrency)) {
      _selectedCurrency = currencies.first;
    }
  }

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;

    final currencies = _currencies;

    if (currencies.isEmpty) {
      return const SizedBox.shrink();
    }

    final selectedCurrency = _selectedCurrency ?? currencies.first;

    final deposit = widget.summary.deposit(selectedCurrency);

    final withdrawal = widget.summary.withdrawal(selectedCurrency);

    final depositCount = widget.summary.depositTransactions(selectedCurrency);

    final withdrawalCount = widget.summary.withdrawalTransactions(
      selectedCurrency,
    );

    return _SummaryCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _CurrencySelector(
            currencies: currencies,
            selectedCurrency: selectedCurrency,
            onSelected: (currency) {
              setState(() {
                _selectedCurrency = currency;
              });
            },
          ),

          SizedBox(height: spacing.md),

          Row(
            children: [
              Expanded(
                child: _SummaryBlock(
                  title: 'Cash In',
                  amount: deposit?.balance ?? 0,
                  usdValue: deposit?.usdValue ?? 0,
                  count: depositCount,
                  color: const Color(0xFFDC2626),
                  currency: selectedCurrency.toUpperCase(),
                ),
              ),

              SizedBox(width: spacing.sm),

              Expanded(
                child: _SummaryBlock(
                  title: 'Cash Out',
                  amount: withdrawal?.balance ?? 0,
                  usdValue: withdrawal?.usdValue ?? 0,
                  count: withdrawalCount,
                  color: const Color(0xFF16A34A),
                  currency: selectedCurrency.toUpperCase(),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    final radius = context.radius;
    final colorScheme = context.colorScheme;

    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(spacing.padding),
      decoration: BoxDecoration(
        color: context.theme.cardColor,
        borderRadius: BorderRadius.circular(radius.cardRadius),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.09),
        ),
      ),
      child: child,
    );
  }
}

class _CurrencySelector extends StatelessWidget {
  const _CurrencySelector({
    required this.currencies,
    required this.selectedCurrency,
    required this.onSelected,
  });

  final List<String> currencies;
  final String selectedCurrency;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (var index = 0; index < currencies.length; index++) ...[
            _CurrencyTab(
              currency: currencies[index].toUpperCase(),
              selected: currencies[index] == selectedCurrency,
              onTap: () {
                onSelected(currencies[index]);
              },
            ),

            if (index < currencies.length - 1) SizedBox(width: spacing.sm),
          ],
        ],
      ),
    );
  }
}

class _CurrencyTab extends StatelessWidget {
  const _CurrencyTab({
    required this.currency,
    required this.selected,
    required this.onTap,
  });

  final String currency;
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
            horizontal: spacing.md,
            vertical: spacing.sm,
          ),
          decoration: BoxDecoration(
            color: selected
                ? colorScheme.primary.withValues(alpha: 0.12)
                : colorScheme.surface,
            borderRadius: BorderRadius.circular(radius.borderRadius),
            border: Border.all(
              color: selected
                  ? colorScheme.primary
                  : colorScheme.outlineVariant,
            ),
          ),
          child: Text(
            currency,
            style: AppTextStyles.small(context).copyWith(
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              color: selected ? colorScheme.primary : colorScheme.onSurface,
            ),
          ),
        ),
      ),
    );
  }
}

class _SummaryBlock extends StatelessWidget {
  const _SummaryBlock({
    required this.title,
    required this.amount,
    required this.usdValue,
    required this.count,
    required this.color,
    required this.currency,
  });

  final String title;
  final double amount;
  final double usdValue;
  final int count;
  final Color color;
  final String currency;

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    final radius = context.radius;
    final colorScheme = context.colorScheme;

    return Container(
      padding: EdgeInsets.all(spacing.sm),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(radius.borderRadius),
        border: Border.all(color: color.withValues(alpha: 0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: AppTextStyles.tiny(
              context,
            ).copyWith(color: color, fontWeight: FontWeight.w700),
          ),

          SizedBox(height: spacing.xs),

          Text(
            NumberFormatService.formatAmount(amount, currency: currency),
            style: AppTextStyles.smallNumber(
              context,
            ).copyWith(fontWeight: FontWeight.w700),
          ),

          SizedBox(height: spacing.xs),

          Text(
            '≈ ${NumberFormatService.formatUsd(usdValue)}',
            style: AppTextStyles.tinyNumber(
              context,
            ).copyWith(color: colorScheme.onSurfaceVariant),
          ),

          SizedBox(height: spacing.xs),

          Text(
            '$count transaction${count == 1 ? '' : 's'}',
            style: AppTextStyles.tiny(
              context,
            ).copyWith(color: colorScheme.onSurfaceVariant),
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
// import 'package:ngoda/data_models/transaction/daily_transaction_summary.dart';
// import 'package:ngoda/services/hive_service.dart';
// import 'package:ngoda/services/number_format_service.dart';
// import 'package:ngoda/ui/enums/enums.dart';
// import 'package:ngoda/ui/extensions/app_size.dart';
// import 'package:ngoda/ui/extensions/theme_extension.dart';
// import 'package:ngoda/ui/functions/compute_net_position.dart';
// import 'package:ngoda/ui/functions/get_user_home_screen_quick_links.dart';
// import 'package:ngoda/ui/functions/is_jwt_expired.dart';
// import 'package:ngoda/ui/screens/auth/providers/auth_provider.dart';
// import 'package:ngoda/ui/screens/vendor/provider/vendor_dashboard_provider.dart';
// import 'package:ngoda/ui/shared/app_text_styles.dart';
// import 'package:ngoda/ui/shared/theme_provider.dart';
// import 'package:ngoda/ui/widgets/app_error_state.dart';
// import 'package:ngoda/ui/widgets/app_loader.dart';
// import 'package:ngoda/ui/widgets/bottom_nav.dart';
// import 'package:ngoda/ui/widgets/dashboard_quick_actions.dart';
// import 'package:ngoda/ui/widgets/fiat_card.dart';
// import 'package:ngoda/ui/widgets/net_position_card.dart';

// class VendorDashboardScreen extends ConsumerWidget {
//   const VendorDashboardScreen({super.key});

//   @override
//   Widget build(BuildContext context, WidgetRef ref) {
//     final spacing = context.spacing;
//     final iconSize = context.iconSize;
//     final colorScheme = context.colorScheme;

//     final asyncData = ref.watch(vendorDashboardProvider);

//     return asyncData.when(
//       loading: () =>
//           const AppLoader(message: 'Loading dashboard', fullScreen: true),
//       error: (error, _) {
//         return _buildErrorState(context, ref, error);
//       },
//       data: (response) {
//         if (response.error != null) {
//           return _buildErrorState(context, ref, response.error!);
//         }

//         final dashboard = response.result;

//         if (dashboard == null) {
//           return const Scaffold(
//             body: AppErrorState(message: 'Dashboard data is unavailable.'),
//           );
//         }

//         /*
//          * Vendor net position continues to use the
//          * existing Vendor dashboard calculation.
//          */
//         final netPosition = computeVendorNetPosition(dashboard);

//         /*
//          * NFC support is device state and is not part
//          * of the Vendor dashboard response.
//          */
//         final nfcSupported =
//             ref
//                 .read(hiveServiceProvider)
//                 .getItem<bool>(HiveBoxName.nfcSupport, 'nfcSupported')
//                 .result ??
//             false;

//         final quickLinks = getUserHomeScreenQuickLinks(
//           context: context,
//           role: UserRole.vendor,
//           iconSize: iconSize.medium,
//           primary: colorScheme.primary,
//           nfcSupported: nfcSupported,
//         );

//         return Scaffold(
//           bottomNavigationBar: const BottomNav(currentIndex: 0),
//           body: SafeArea(
//             child: RefreshIndicator(
//               onRefresh: () async {
//                 ref.invalidate(vendorDashboardProvider);

//                 await ref.read(vendorDashboardProvider.future);
//               },
//               child: ListView(
//                 physics: const AlwaysScrollableScrollPhysics(),
//                 padding: EdgeInsets.fromLTRB(
//                   spacing.md,
//                   spacing.md,
//                   spacing.md,
//                   spacing.lg,
//                 ),
//                 children: [
//                   _DashboardHeader(
//                     onThemeChanged: () {
//                       ref.read(themeModeProvider.notifier).toggle();
//                     },
//                     themeMode: ref.watch(themeModeProvider),
//                   ),

//                   SizedBox(height: spacing.lg),

//                   NetPositionCard(amount: netPosition),

//                   if (quickLinks.isNotEmpty) ...[
//                     SizedBox(height: spacing.md),
//                     DashboardQuickActions(quickLinks: quickLinks),
//                   ],

//                   SizedBox(height: spacing.lg),

//                   /*
//                    * Merchant activity.
//                    */
//                   const _SectionLabel(
//                     title: 'Merchant',
//                     description:
//                         'Your merchant balance and today\'s payment activity.',
//                   ),

//                   SizedBox(height: spacing.sm),

//                   FiatCard(wallet: dashboard.merchantWallet),

//                   SizedBox(height: spacing.sm),

//                   DailyPaymentSummaryCard(summary: dashboard.dailySummary),

//                   SizedBox(height: spacing.lg),

//                   /*
//                    * Agent activity.
//                    */
//                   const _SectionLabel(
//                     title: 'Agent',
//                     description:
//                         'Your agent balance and today\'s cash activity.',
//                   ),

//                   SizedBox(height: spacing.sm),

//                   FiatCard(wallet: dashboard.agentWallet),

//                   SizedBox(height: spacing.sm),

//                   DailySummaryCard(summary: dashboard.dailySummary),

//                   SizedBox(height: spacing.lg),

//                   /*
//                    * Personal/customer wallet.
//                    */
//                   const _SectionLabel(
//                     title: 'Personal',
//                     description: 'Your personal wallet balances.',
//                   ),

//                   SizedBox(height: spacing.sm),

//                   FiatCard(wallet: dashboard.customerWallet),
//                 ],
//               ),
//             ),
//           ),
//         );
//       },
//     );
//   }

//   Widget _buildErrorState(BuildContext context, WidgetRef ref, Object error) {
//     if (!isJwtExpired(error)) {
//       return Scaffold(
//         body: AppErrorState(
//           message: error.toString(),
//           buttonText: 'Retry',
//           onAction: () {
//             ref.invalidate(vendorDashboardProvider);
//           },
//         ),
//       );
//     }

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

// class _DashboardHeader extends StatelessWidget {
//   const _DashboardHeader({
//     required this.onThemeChanged,
//     required this.themeMode,
//   });

//   final VoidCallback onThemeChanged;
//   final ThemeMode themeMode;

//   @override
//   Widget build(BuildContext context) {
//     final spacing = context.spacing;
//     final colorScheme = context.colorScheme;

//     return Row(
//       crossAxisAlignment: CrossAxisAlignment.center,
//       children: [
//         Expanded(
//           child: Column(
//             crossAxisAlignment: CrossAxisAlignment.start,
//             children: [
//               Text(
//                 'Welcome back',
//                 style: AppTextStyles.large(
//                   context,
//                 ).copyWith(fontWeight: FontWeight.w700),
//               ),
//               SizedBox(height: spacing.xs),
//               Text(
//                 'Your financial position',
//                 style: AppTextStyles.small(
//                   context,
//                 ).copyWith(color: colorScheme.onSurfaceVariant),
//               ),
//             ],
//           ),
//         ),
//         IconButton(
//           tooltip: themeMode == ThemeMode.dark
//               ? 'Use light theme'
//               : 'Use dark theme',
//           onPressed: onThemeChanged,
//           icon: Icon(
//             themeMode == ThemeMode.dark
//                 ? Icons.light_mode_outlined
//                 : Icons.dark_mode_outlined,
//             color: colorScheme.primary,
//           ),
//         ),
//       ],
//     );
//   }
// }

// class _SectionLabel extends StatelessWidget {
//   const _SectionLabel({required this.title, required this.description});

//   final String title;
//   final String description;

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
//           description,
//           style: AppTextStyles.tiny(
//             context,
//           ).copyWith(color: colorScheme.onSurfaceVariant),
//         ),
//       ],
//     );
//   }
// }

// // class _QuickActions extends StatelessWidget {
// //   const _QuickActions({required this.quickLinks});

// //   final List<Widget> quickLinks;

// //   @override
// //   Widget build(BuildContext context) {
// //     final spacing = context.spacing;

// //     return Column(
// //       crossAxisAlignment: CrossAxisAlignment.start,
// //       children: [
// //         Text(
// //           'Quick actions',
// //           style: AppTextStyles.tiny(
// //             context,
// //           ).copyWith(fontWeight: FontWeight.w700),
// //         ),
// //         SizedBox(height: spacing.sm),
// //         SingleChildScrollView(
// //           scrollDirection: Axis.horizontal,
// //           child: Row(
// //             children: [
// //               for (var index = 0; index < quickLinks.length; index++) ...[
// //                 quickLinks[index],
// //                 if (index < quickLinks.length - 1) SizedBox(width: spacing.sm),
// //               ],
// //             ],
// //           ),
// //         ),
// //       ],
// //     );
// //   }
// // }

// /*
//  * Merchant payment activity.
//  *
//  * Vendor payment activity uses the `payments`
//  * portion of DailyTransactionSummary.
//  */
// class DailyPaymentSummaryCard extends StatefulWidget {
//   const DailyPaymentSummaryCard({super.key, required this.summary});

//   final DailyTransactionSummary summary;

//   @override
//   State<DailyPaymentSummaryCard> createState() =>
//       _DailyPaymentSummaryCardState();
// }

// class _DailyPaymentSummaryCardState extends State<DailyPaymentSummaryCard> {
//   String? _selectedCurrency;

//   List<String> get _currencies {
//     final currencies = {
//       ...widget.summary.payments.keys,
//       ...widget.summary.paymentCount.keys,
//     }.toList()..sort();

//     return currencies;
//   }

//   @override
//   void initState() {
//     super.initState();

//     final currencies = _currencies;

//     if (currencies.isNotEmpty) {
//       _selectedCurrency = currencies.first;
//     }
//   }

//   @override
//   void didUpdateWidget(covariant DailyPaymentSummaryCard oldWidget) {
//     super.didUpdateWidget(oldWidget);

//     final currencies = _currencies;

//     if (currencies.isEmpty) {
//       _selectedCurrency = null;
//       return;
//     }

//     if (_selectedCurrency == null || !currencies.contains(_selectedCurrency)) {
//       _selectedCurrency = currencies.first;
//     }
//   }

//   @override
//   Widget build(BuildContext context) {
//     final spacing = context.spacing;

//     final currencies = _currencies;

//     if (currencies.isEmpty) {
//       return const SizedBox.shrink();
//     }

//     final selectedCurrency = _selectedCurrency ?? currencies.first;

//     final payment = widget.summary.payment(selectedCurrency);

//     final paymentCount = widget.summary.paymentTransactions(selectedCurrency);

//     return _SummaryCard(
//       child: Column(
//         crossAxisAlignment: CrossAxisAlignment.stretch,
//         children: [
//           _CurrencySelector(
//             currencies: currencies,
//             selectedCurrency: selectedCurrency,
//             onSelected: (currency) {
//               setState(() {
//                 _selectedCurrency = currency;
//               });
//             },
//           ),
//           SizedBox(height: spacing.md),
//           _SummaryBlock(
//             title: 'Incoming Payments',
//             amount: payment?.balance ?? 0,
//             usdValue: payment?.usdValue ?? 0,
//             count: paymentCount,
//             color: const Color(0xFF16A34A),
//             currency: selectedCurrency.toUpperCase(),
//           ),
//         ],
//       ),
//     );
//   }
// }

// /*
//  * Agent cash activity.
//  *
//  * Deposits and withdrawals remain separate
//  * from merchant payment activity.
//  */
// class DailySummaryCard extends StatefulWidget {
//   const DailySummaryCard({super.key, required this.summary});

//   final DailyTransactionSummary summary;

//   @override
//   State<DailySummaryCard> createState() => _DailySummaryCardState();
// }

// class _DailySummaryCardState extends State<DailySummaryCard> {
//   String? _selectedCurrency;

//   List<String> get _currencies {
//     final currencies = {
//       ...widget.summary.deposits.keys,
//       ...widget.summary.withdrawals.keys,
//       ...widget.summary.depositCount.keys,
//       ...widget.summary.withdrawalCount.keys,
//     }.toList()..sort();

//     return currencies;
//   }

//   @override
//   void initState() {
//     super.initState();

//     final currencies = _currencies;

//     if (currencies.isNotEmpty) {
//       _selectedCurrency = currencies.first;
//     }
//   }

//   @override
//   void didUpdateWidget(covariant DailySummaryCard oldWidget) {
//     super.didUpdateWidget(oldWidget);

//     final currencies = _currencies;

//     if (currencies.isEmpty) {
//       _selectedCurrency = null;
//       return;
//     }

//     if (_selectedCurrency == null || !currencies.contains(_selectedCurrency)) {
//       _selectedCurrency = currencies.first;
//     }
//   }

//   @override
//   Widget build(BuildContext context) {
//     final spacing = context.spacing;

//     final currencies = _currencies;

//     if (currencies.isEmpty) {
//       return const SizedBox.shrink();
//     }

//     final selectedCurrency = _selectedCurrency ?? currencies.first;

//     final deposit = widget.summary.deposit(selectedCurrency);

//     final withdrawal = widget.summary.withdrawal(selectedCurrency);

//     final depositCount = widget.summary.depositTransactions(selectedCurrency);

//     final withdrawalCount = widget.summary.withdrawalTransactions(
//       selectedCurrency,
//     );

//     return _SummaryCard(
//       child: Column(
//         crossAxisAlignment: CrossAxisAlignment.stretch,
//         children: [
//           _CurrencySelector(
//             currencies: currencies,
//             selectedCurrency: selectedCurrency,
//             onSelected: (currency) {
//               setState(() {
//                 _selectedCurrency = currency;
//               });
//             },
//           ),
//           SizedBox(height: spacing.md),
//           Row(
//             children: [
//               Expanded(
//                 child: _SummaryBlock(
//                   title: 'Cash In',
//                   amount: deposit?.balance ?? 0,
//                   usdValue: deposit?.usdValue ?? 0,
//                   count: depositCount,
//                   color: const Color(0xFFDC2626),
//                   currency: selectedCurrency.toUpperCase(),
//                 ),
//               ),
//               SizedBox(width: spacing.sm),
//               Expanded(
//                 child: _SummaryBlock(
//                   title: 'Cash Out',
//                   amount: withdrawal?.balance ?? 0,
//                   usdValue: withdrawal?.usdValue ?? 0,
//                   count: withdrawalCount,
//                   color: const Color(0xFF16A34A),
//                   currency: selectedCurrency.toUpperCase(),
//                 ),
//               ),
//             ],
//           ),
//         ],
//       ),
//     );
//   }
// }

// class _SummaryCard extends StatelessWidget {
//   const _SummaryCard({required this.child});

//   final Widget child;

//   @override
//   Widget build(BuildContext context) {
//     final spacing = context.spacing;
//     final radius = context.radius;

//     return Container(
//       width: double.infinity,
//       padding: EdgeInsets.all(spacing.padding),
//       decoration: BoxDecoration(
//         color: Theme.of(context).cardColor,
//         borderRadius: BorderRadius.circular(radius.borderRadius),
//       ),
//       child: child,
//     );
//   }
// }

// class _CurrencySelector extends StatelessWidget {
//   const _CurrencySelector({
//     required this.currencies,
//     required this.selectedCurrency,
//     required this.onSelected,
//   });

//   final List<String> currencies;
//   final String selectedCurrency;
//   final ValueChanged<String> onSelected;

//   @override
//   Widget build(BuildContext context) {
//     final spacing = context.spacing;

//     return SingleChildScrollView(
//       scrollDirection: Axis.horizontal,
//       child: Row(
//         children: [
//           for (var index = 0; index < currencies.length; index++) ...[
//             _CurrencyTab(
//               currency: currencies[index].toUpperCase(),
//               selected: currencies[index] == selectedCurrency,
//               onTap: () {
//                 onSelected(currencies[index]);
//               },
//             ),
//             if (index < currencies.length - 1) SizedBox(width: spacing.sm),
//           ],
//         ],
//       ),
//     );
//   }
// }

// class _CurrencyTab extends StatelessWidget {
//   const _CurrencyTab({
//     required this.currency,
//     required this.selected,
//     required this.onTap,
//   });

//   final String currency;
//   final bool selected;
//   final VoidCallback onTap;

//   @override
//   Widget build(BuildContext context) {
//     final spacing = context.spacing;
//     final radius = context.radius;
//     final colorScheme = context.colorScheme;

//     return Material(
//       color: Colors.transparent,
//       child: InkWell(
//         onTap: onTap,
//         borderRadius: BorderRadius.circular(radius.borderRadius),
//         child: AnimatedContainer(
//           duration: const Duration(milliseconds: 180),
//           padding: EdgeInsets.symmetric(
//             horizontal: spacing.md,
//             vertical: spacing.sm,
//           ),
//           decoration: BoxDecoration(
//             color: selected
//                 ? colorScheme.primary.withValues(alpha: 0.12)
//                 : colorScheme.surface,
//             borderRadius: BorderRadius.circular(radius.borderRadius),
//             border: Border.all(
//               color: selected
//                   ? colorScheme.primary
//                   : colorScheme.outlineVariant,
//             ),
//           ),
//           child: Text(
//             currency,
//             style: AppTextStyles.small(context).copyWith(
//               fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
//               color: selected ? colorScheme.primary : colorScheme.onSurface,
//             ),
//           ),
//         ),
//       ),
//     );
//   }
// }

// class _SummaryBlock extends StatelessWidget {
//   const _SummaryBlock({
//     required this.title,
//     required this.amount,
//     required this.usdValue,
//     required this.count,
//     required this.color,
//     required this.currency,
//   });

//   final String title;
//   final double amount;
//   final double usdValue;
//   final int count;
//   final Color color;
//   final String currency;

//   @override
//   Widget build(BuildContext context) {
//     final spacing = context.spacing;
//     final radius = context.radius;
//     final colorScheme = context.colorScheme;

//     return Container(
//       padding: EdgeInsets.all(spacing.sm),
//       decoration: BoxDecoration(
//         color: color.withValues(alpha: 0.08),
//         borderRadius: BorderRadius.circular(radius.borderRadius),
//         border: Border.all(color: color.withValues(alpha: 0.18)),
//       ),
//       child: Column(
//         crossAxisAlignment: CrossAxisAlignment.start,
//         children: [
//           Text(
//             title,
//             style: AppTextStyles.tiny(
//               context,
//             ).copyWith(color: color, fontWeight: FontWeight.w700),
//           ),

//           SizedBox(height: spacing.xs),

//           Text(
//             NumberFormatService.formatAmount(amount, currency: currency),
//             style: AppTextStyles.smallNumber(
//               context,
//             ).copyWith(fontWeight: FontWeight.w700),
//           ),

//           SizedBox(height: spacing.xs),

//           Text(
//             '≈ ${NumberFormatService.formatUsd(usdValue)}',
//             style: AppTextStyles.tinyNumber(
//               context,
//             ).copyWith(color: colorScheme.onSurfaceVariant),
//           ),

//           SizedBox(height: spacing.xs),

//           Text(
//             '$count transaction${count == 1 ? '' : 's'}',
//             style: AppTextStyles.tiny(
//               context,
//             ).copyWith(color: colorScheme.onSurfaceVariant),
//           ),
//         ],
//       ),
//     );
//   }
// }
