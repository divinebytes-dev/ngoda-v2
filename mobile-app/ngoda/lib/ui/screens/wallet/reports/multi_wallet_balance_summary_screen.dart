import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:ngoda/data_models/currency/currency_balance.dart';
import 'package:ngoda/data_models/wallet/wallet_balance_summary.dart';
import 'package:ngoda/services/currency_service.dart';
import 'package:ngoda/services/number_format_service.dart';
import 'package:ngoda/ui/extensions/app_size.dart';
import 'package:ngoda/ui/extensions/theme_extension.dart';
import 'package:ngoda/ui/functions/get_current_user.dart';
import 'package:ngoda/ui/screens/wallet/reports/provider/multi_wallet_summary_provider.dart';
import 'package:ngoda/ui/shared/app_text_styles.dart';
import 'package:ngoda/ui/widgets/app_empty_state.dart';
import 'package:ngoda/ui/widgets/app_error_state.dart';
import 'package:ngoda/ui/widgets/app_loader.dart';
import 'package:ngoda/ui/widgets/bottom_nav.dart';
import 'package:ngoda/ui/widgets/screen_header.dart';
import 'package:ngoda/ui/widgets/view_header.dart';

class MultiWalletBalanceSummaryScreen extends ConsumerWidget {
  const MultiWalletBalanceSummaryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final walletSummary = ref.watch(multiWalletSummaryProvider);

    final role = getCurrentUser().role;
    final isMerchant = role == 'merchant';
    void closeScreen() {
      ref.invalidate(multiWalletSummaryProvider);

      context.pop();
    }

    Future<void> refresh() async {
      ref.invalidate(multiWalletSummaryProvider);

      await ref.read(multiWalletSummaryProvider.future);
    }

    return Scaffold(
      bottomNavigationBar: isMerchant ? const BottomNav(currentIndex: 2) : null,
      body: SafeArea(
        child: Column(
          children: [
            isMerchant
                ? ScreenHeader(title: 'Wallet Balance Summary')
                : ViewHeader(
                    title: 'Wallet Balance Summary',
                    onClose: closeScreen,
                  ),
            Expanded(
              child: RefreshIndicator(
                onRefresh: refresh,
                child: walletSummary.when(
                  loading: () => const AppLoader(
                    message: 'Loading wallet summary',
                    fullScreen: true,
                  ),
                  error: (error, stackTrace) {
                    return _RefreshableState(
                      child: AppErrorState(message: error.toString()),
                    );
                  },
                  data: (data) {
                    if (data.error != null) {
                      return _RefreshableState(
                        child: AppErrorState(message: data.error.toString()),
                      );
                    }

                    final result = data.result;

                    if (result == null) {
                      return const _EmptyWalletSummary();
                    }

                    final List<_WalletSummaryItem> wallets;

                    if (role == 'merchant') {
                      wallets = [
                        _WalletSummaryItem(
                          title: 'Merchant Wallet',
                          ownerType: 'merchant',
                          summary: result.merchantWallet,
                        ),
                        _WalletSummaryItem(
                          title: 'Agent Wallet',
                          ownerType: 'agent',
                          summary: result.agentWallet,
                        ),
                      ];
                    } else if (role == 'agent') {
                      wallets = [
                        _WalletSummaryItem(
                          title: 'Agent Wallet',
                          ownerType: 'agent',
                          summary: result.agentWallet,
                        ),
                        _WalletSummaryItem(
                          title: 'Personal Wallet',
                          ownerType: 'customer',
                          summary: result.customerWallet,
                        ),
                      ];
                    } else if (role == 'vendor') {
                      wallets = [
                        _WalletSummaryItem(
                          title: 'Merchant Wallet',
                          ownerType: 'merchant',
                          summary: result.merchantWallet,
                        ),
                        _WalletSummaryItem(
                          title: 'Agent Wallet',
                          ownerType: 'agent',
                          summary: result.agentWallet,
                        ),
                        _WalletSummaryItem(
                          title: 'Personal Wallet',
                          ownerType: 'customer',
                          summary: result.customerWallet,
                        ),
                      ];
                    } else {
                      return const _EmptyWalletSummary();
                    }

                    return _MultiWalletSummaryContent(wallets: wallets);
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _WalletSummaryItem {
  const _WalletSummaryItem({
    required this.title,
    required this.ownerType,
    required this.summary,
  });

  final String title;
  final String ownerType;
  final WalletBalanceSummary summary;
}

class _MultiWalletSummaryContent extends StatelessWidget {
  const _MultiWalletSummaryContent({required this.wallets});

  final List<_WalletSummaryItem> wallets;

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;

    final hasBalances = wallets.any(
      (wallet) => wallet.summary.sortedCurrencyList.isNotEmpty,
    );

    if (!hasBalances) {
      return const _EmptyWalletSummary();
    }

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: EdgeInsets.fromLTRB(
        spacing.md,
        spacing.sm,
        spacing.md,
        spacing.lg,
      ),
      children: [
        for (var index = 0; index < wallets.length; index++) ...[
          _WalletSummarySection(
            item: wallets[index],
            walletOwner: wallets[index].ownerType,
          ),
          if (index < wallets.length - 1) SizedBox(height: spacing.xl),
        ],
      ],
    );
  }
}

class _WalletSummarySection extends StatelessWidget {
  const _WalletSummarySection({required this.item, required this.walletOwner});

  final _WalletSummaryItem item;
  final String walletOwner;

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;

    final summary = item.summary;
    final currencies = summary.sortedCurrencyList.toList();

    final user = getCurrentUser();

    String path = '/vendor-wallet/';

    if (user.role == 'agent') {
      path = '/agent-wallet/';
    } else if (user.role == 'merchant') {
      path = '/merchant-wallet/';
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _WalletHeader(title: item.title, ownerType: item.ownerType),

        SizedBox(height: spacing.sm),

        _TotalBalanceCard(
          totalBalance: summary.totalUsdValue,
          ownerType: item.ownerType,
          children: [
            const _SectionHeader(
              title: 'Balance breakdown',
              description: 'Your available wallet balances by currency.',
            ),

            SizedBox(height: spacing.sm),

            if (currencies.isEmpty)
              const _EmptyWalletSection()
            else
              for (var index = 0; index < currencies.length; index++) ...[
                _buildCurrencyCard(
                  context: context,
                  summary: summary,
                  currencyCode: currencies[index],
                  path: path,
                ),

                if (index < currencies.length - 1) SizedBox(height: spacing.sm),
              ],
          ],
        ),
      ],
    );
  }

  Widget _buildCurrencyCard({
    required BuildContext context,
    required WalletBalanceSummary summary,
    required String currencyCode,
    required String path,
  }) {
    final balance = summary.walletBalances.getByCurrency(currencyCode);

    if (balance == null) {
      return const SizedBox.shrink();
    }

    return _CurrencyBalanceCard(
      currencyCode: currencyCode,
      balance: balance,
      onTap: () {
        context.push(
          '$path'
          '${walletOwner.toLowerCase()}/'
          '${currencyCode.toLowerCase()}',
        );
      },
    );
  }
}

class _WalletHeader extends StatelessWidget {
  const _WalletHeader({required this.title, required this.ownerType});

  final String title;
  final String ownerType;

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    final iconSize = context.iconSize;
    final colorScheme = context.colorScheme;

    final sectionColor = _walletSectionColor(ownerType, colorScheme);

    return Row(
      children: [
        Container(
          padding: EdgeInsets.all(spacing.sm),
          decoration: BoxDecoration(
            color: sectionColor.withValues(alpha: 0.12),
            shape: BoxShape.circle,
          ),
          child: Icon(
            _walletIcon(ownerType),
            size: iconSize.xl,
            color: sectionColor,
          ),
        ),

        SizedBox(width: spacing.sm),

        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: AppTextStyles.medium(
                  context,
                ).copyWith(color: sectionColor, fontWeight: FontWeight.w700),
              ),

              SizedBox(height: spacing.xs),

              Text(
                _walletDescription(ownerType),
                style: AppTextStyles.tiny(
                  context,
                ).copyWith(color: colorScheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, required this.description});

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
          style: AppTextStyles.medium(
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

class _TotalBalanceCard extends StatelessWidget {
  const _TotalBalanceCard({
    required this.totalBalance,
    required this.ownerType,
    required this.children,
  });

  final double totalBalance;
  final String ownerType;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    final colorScheme = context.colorScheme;
    final iconSize = context.iconSize;

    final sectionColor = _walletSectionColor(ownerType, colorScheme);

    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(spacing.lg),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor, //colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(spacing.md),
        border: Border.all(color: sectionColor.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: EdgeInsets.all(spacing.sm),
                decoration: BoxDecoration(
                  color: sectionColor.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  _walletIcon(ownerType),
                  color: sectionColor,
                  size: iconSize.large,
                ),
              ),

              SizedBox(width: spacing.sm),

              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Total wallet balance',
                      style: AppTextStyles.small(
                        context,
                      ).copyWith(fontWeight: FontWeight.w600),
                    ),

                    SizedBox(height: spacing.xs),

                    Text(
                      'USD equivalent across all currencies',
                      style: AppTextStyles.tiny(
                        context,
                      ).copyWith(color: colorScheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
            ],
          ),

          SizedBox(height: spacing.lg),

          Text(
            NumberFormatService.formatAmount(totalBalance, currency: 'usd'),
            style: AppTextStyles.mediumNumber(
              context,
            ).copyWith(color: sectionColor),
          ),

          SizedBox(height: spacing.lg),

          ...children,
        ],
      ),
    );
  }
}

class _CurrencyBalanceCard extends StatelessWidget {
  const _CurrencyBalanceCard({
    required this.balance,
    required this.currencyCode,
    required this.onTap,
  });

  final CurrencyBalance balance;
  final String currencyCode;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    final colorScheme = context.colorScheme;

    final currencyName = CurrencyService.name(currencyCode);

    final currencySymbol = CurrencyService.symbol(currencyCode);

    return Material(
      color: Theme.of(context).cardColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(spacing.md),
        side: BorderSide(
          color: colorScheme.outlineVariant.withValues(alpha: 0.09),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(spacing.md),
        child: Padding(
          padding: EdgeInsets.all(spacing.md),
          child: Row(
            children: [
              _CurrencyIcon(code: currencyCode, symbol: currencySymbol),

              SizedBox(width: spacing.md),

              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      currencyName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.small(
                        context,
                      ).copyWith(fontWeight: FontWeight.w600),
                    ),

                    SizedBox(height: spacing.xs),

                    Text(
                      currencyCode.toUpperCase(),
                      style: AppTextStyles.tiny(
                        context,
                      ).copyWith(color: colorScheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),

              SizedBox(width: spacing.sm),

              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    NumberFormatService.formatAmount(
                      balance.balance,
                      currency: currencyCode,
                    ),
                    style: AppTextStyles.smallNumber(context),
                  ),

                  SizedBox(height: spacing.xs),

                  Text(
                    NumberFormatService.formatAmount(
                      balance.usdValue,
                      currency: 'usd',
                    ),
                    style: AppTextStyles.tinyNumber(
                      context,
                    ).copyWith(color: colorScheme.onSurfaceVariant),
                  ),
                ],
              ),

              SizedBox(width: spacing.sm),

              Icon(
                Icons.chevron_right_rounded,
                color: colorScheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CurrencyIcon extends StatelessWidget {
  const _CurrencyIcon({required this.code, required this.symbol});

  final String code;
  final String symbol;

  static const Color _gold = Color(0xFFD4AF37);

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;

    final fallback = code.isEmpty
        ? '?'
        : code.substring(0, code.length >= 2 ? 2 : code.length).toUpperCase();

    return Container(
      width: spacing.xxxl,
      height: spacing.xxxl,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: _gold.withValues(alpha: 0.12),
        shape: BoxShape.circle,
        border: Border.all(color: _gold.withValues(alpha: 0.25)),
      ),
      child: Text(
        symbol.isNotEmpty ? symbol : fallback,
        style: symbol == 'GOLD'
            ? AppTextStyles.tiny(
                context,
              ).copyWith(color: _gold, fontWeight: FontWeight.w700)
            : AppTextStyles.small(
                context,
              ).copyWith(color: _gold, fontWeight: FontWeight.w700),
      ),
    );
  }
}

class _EmptyWalletSummary extends StatelessWidget {
  const _EmptyWalletSummary();

  @override
  Widget build(BuildContext context) {
    return const _RefreshableState(child: AppEmptyState());
  }
}

class _EmptyWalletSection extends StatelessWidget {
  const _EmptyWalletSection();

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    final colorScheme = context.colorScheme;

    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(spacing.md),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(spacing.md),
      ),
      child: Text(
        'No wallet balances available',
        textAlign: TextAlign.center,
        style: AppTextStyles.tiny(
          context,
        ).copyWith(color: colorScheme.onSurfaceVariant),
      ),
    );
  }
}

class _RefreshableState extends StatelessWidget {
  const _RefreshableState({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        SizedBox(
          height: MediaQuery.sizeOf(context).height * 0.65,
          child: child,
        ),
      ],
    );
  }
}

Color _walletSectionColor(String ownerType, ColorScheme colorScheme) {
  switch (ownerType) {
    case 'merchant':
      return const Color(0xFFD4AF37);

    case 'agent':
      return const Color(0xFF3B82F6);

    case 'customer':
      return const Color(0xFF16A34A);

    default:
      return colorScheme.primary;
  }
}

IconData _walletIcon(String ownerType) {
  switch (ownerType) {
    case 'merchant':
      return Icons.storefront_outlined;

    case 'agent':
      return Icons.account_balance_wallet_outlined;

    case 'customer':
      return Icons.person_outline;

    default:
      return Icons.wallet_outlined;
  }
}

String _walletDescription(String ownerType) {
  switch (ownerType) {
    case 'merchant':
      return 'Merchant funds';

    case 'agent':
      return 'Agent funds';

    case 'customer':
      return 'Personal funds';

    default:
      return 'Wallet funds';
  }
}
