import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:ngoda/data_models/blockchain/blockchain_wallet_balance.dart';

import 'package:ngoda/data_models/currency/currency_balance.dart';
import 'package:ngoda/data_models/wallet/wallet_balance_summary.dart';
import 'package:ngoda/services/currency_service.dart';
import 'package:ngoda/services/number_format_service.dart';
import 'package:ngoda/ui/extensions/app_size.dart';
import 'package:ngoda/ui/extensions/theme_extension.dart';
import 'package:ngoda/ui/functions/get_current_user.dart';
import 'package:ngoda/ui/screens/wallet/reports/provider/wallet_summary_provider.dart';
import 'package:ngoda/ui/shared/app_text_styles.dart';
import 'package:ngoda/ui/widgets/app_empty_state.dart';
import 'package:ngoda/ui/widgets/app_error_state.dart';
import 'package:ngoda/ui/widgets/app_loader.dart';
import 'package:ngoda/ui/widgets/bottom_nav.dart';
import 'package:ngoda/ui/widgets/screen_header.dart';
import 'package:ngoda/ui/widgets/view_header.dart';

class WalletBalanceSummaryScreen extends ConsumerWidget {
  const WalletBalanceSummaryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final walletSummary = ref.watch(walletSummaryProvider);

    final user = getCurrentUser();
    final role = user.role;

    final showBottomNav = role != 'customer';

    final header = role == 'customer'
        ? ViewHeader(
            title: 'Wallet Balance Summary',
            onClose: () {
              ref.invalidate(walletSummaryProvider);
              context.pop();
            },
          )
        : const ScreenHeader(title: 'Wallet Balance Summary');

    return Scaffold(
      bottomNavigationBar: showBottomNav
          ? const BottomNav(currentIndex: 2)
          : null,
      body: SafeArea(
        child: Column(
          children: [
            header,
            Expanded(
              child: RefreshIndicator(
                onRefresh: () => _refresh(ref),
                child: walletSummary.when(
                  loading: () => const AppLoader(
                    message: 'Loading wallet summary',
                    fullScreen: true,
                  ),
                  error: (error, _) =>
                      _RefreshableError(message: error.toString()),
                  data: (response) {
                    if (response.error != null) {
                      return _RefreshableError(
                        message: response.error.toString(),
                      );
                    }

                    final summary = response.result;

                    if (summary == null ||
                        (summary.sortedCurrencyList.isEmpty &&
                            summary.blockchainBalances.isEmpty)) {
                      return const _RefreshableEmpty();
                    }

                    return _WalletSummaryContent(summary: summary);
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _refresh(WidgetRef ref) async {
    ref.invalidate(walletSummaryProvider);
    await ref.read(walletSummaryProvider.future);
  }
}

class _WalletSummaryContent extends StatelessWidget {
  const _WalletSummaryContent({required this.summary});

  final WalletBalanceSummary summary;

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    final user = getCurrentUser();

    // Keep the existing navigation paths for both fiat and GOLD.
    final path = user.role == 'treasury'
        ? '/treasury-wallet/treasury/'
        : '/customer-wallet/customer/';

    // GOLD is displayed by blockchain, not as a consolidated
    // clickable currency card.
    final currencies = summary.sortedCurrencyList
        .where((currency) => currency.toLowerCase() != 'gold')
        .toList();

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: EdgeInsets.fromLTRB(
        spacing.md,
        spacing.sm,
        spacing.md,
        spacing.lg,
      ),
      children: [
        _TotalBalanceCard(totalBalance: summary.totalUsdValue),

        SizedBox(height: spacing.lg),

        if (currencies.isNotEmpty) ...[
          const _SectionHeader(
            title: 'Balance breakdown',
            description: 'Your available wallet balances by currency.',
          ),

          SizedBox(height: spacing.sm),

          for (var index = 0; index < currencies.length; index++) ...[
            _buildCurrencyCard(
              context: context,
              currencyCode: currencies[index],
              path: path,
            ),
            if (index < currencies.length - 1) SizedBox(height: spacing.sm),
          ],
        ],

        if (summary.blockchainBalances.isNotEmpty) ...[
          SizedBox(height: spacing.lg),

          const _SectionHeader(
            title: 'Blockchain breakdown',
            description: 'Your wallet balances on each supported blockchain.',
          ),

          SizedBox(height: spacing.sm),

          _BlockchainBreakdownCard(
            balances: summary.blockchainBalances,
            onBalanceTap: (balance) {
              _openWalletBalance(
                context: context,
                path: path,
                currencyCode: balance.currencyCode,
                blockchainCode: balance.blockchainCode,
              );
            },
          ),
        ],
      ],
    );
  }

  // Both fiat and GOLD use the same existing route.
  // Fiat passes no extra, while GOLD passes its blockchain code.
  void _openWalletBalance({
    required BuildContext context,
    required String path,
    required String currencyCode,
    String? blockchainCode,
  }) {
    final route = '$path${currencyCode.toLowerCase()}';

    if (blockchainCode == null || blockchainCode.isEmpty) {
      context.push(route);
      return;
    }

    context.push(route, extra: blockchainCode);
  }

  Widget _buildCurrencyCard({
    required BuildContext context,
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
        _openWalletBalance(
          context: context,
          path: path,
          currencyCode: currencyCode,
        );
      },
    );
  }
}

class _BlockchainBreakdownCard extends StatelessWidget {
  const _BlockchainBreakdownCard({
    required this.balances,
    required this.onBalanceTap,
  });

  final List<BlockchainWalletBalance> balances;
  final ValueChanged<BlockchainWalletBalance> onBalanceTap;

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    final colorScheme = context.colorScheme;

    final sortedBalances = [...balances]
      ..sort((first, second) {
        final blockchainComparison = first.blockchainCode.compareTo(
          second.blockchainCode,
        );

        if (blockchainComparison != 0) {
          return blockchainComparison;
        }

        return first.currencyCode.compareTo(second.currencyCode);
      });

    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(spacing.sm),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(context.radius.cardRadius),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.09),
        ),
      ),
      child: Column(
        children: [
          for (var index = 0; index < sortedBalances.length; index++) ...[
            _BlockchainBalanceRow(
              balance: sortedBalances[index],
              onTap: () {
                onBalanceTap(sortedBalances[index]);
              },
            ),
            if (index < sortedBalances.length - 1) SizedBox(height: spacing.sm),
          ],
        ],
      ),
    );
  }
}

class _BlockchainBalanceRow extends StatelessWidget {
  const _BlockchainBalanceRow({required this.balance, required this.onTap});

  final BlockchainWalletBalance balance;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    final colorScheme = context.colorScheme;

    final blockchainCode = balance.blockchainCode;

    final blockchainName = blockchainCode.isEmpty
        ? 'Unknown blockchain'
        : '${blockchainCode[0].toUpperCase()}'
              '${blockchainCode.substring(1)}';

    final currencyCode = balance.currencyCode;

    return Material(
      color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
      borderRadius: BorderRadius.circular(context.radius.md),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: EdgeInsets.all(spacing.sm),
          child: Row(
            children: [
              Container(
                padding: EdgeInsets.all(spacing.sm),
                decoration: BoxDecoration(
                  color: colorScheme.primary.withValues(alpha: 0.10),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.account_tree_outlined,
                  size: context.iconSize.medium,
                  color: colorScheme.primary,
                ),
              ),

              SizedBox(width: spacing.sm),

              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      blockchainName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.small(
                        context,
                      ).copyWith(fontWeight: FontWeight.w700),
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
                    style: AppTextStyles.smallNumber(context).copyWith(
                      fontWeight: FontWeight.w700,
                      color: colorScheme.primary,
                    ),
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
                size: context.iconSize.medium,
              ),
            ],
          ),
        ),
      ),
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
  const _TotalBalanceCard({required this.totalBalance});

  final double totalBalance;

  static const Color _gold = Color(0xFFD4AF37);

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    final iconSize = context.iconSize;
    final colorScheme = context.colorScheme;

    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(spacing.lg),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(spacing.md),
        border: Border.all(color: _gold.withValues(alpha: 0.30)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: EdgeInsets.all(spacing.sm),
                decoration: BoxDecoration(
                  color: _gold.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.account_balance_wallet_outlined,
                  color: _gold,
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
            style: AppTextStyles.mediumNumber(context),
          ),
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
    final radius = context.radius;
    final colorScheme = context.colorScheme;

    final currencyName = CurrencyService.name(currencyCode);
    final currencySymbol = CurrencyService.symbol(currencyCode);

    return Material(
      color: colorScheme.surfaceContainer,
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

class _RefreshableError extends StatelessWidget {
  const _RefreshableError({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        SizedBox(
          height: MediaQuery.sizeOf(context).height * 0.65,
          child: AppErrorState(message: message),
        ),
      ],
    );
  }
}

class _RefreshableEmpty extends StatelessWidget {
  const _RefreshableEmpty();

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        SizedBox(
          height: MediaQuery.sizeOf(context).height * 0.65,
          child: const AppEmptyState(),
        ),
      ],
    );
  }
}

// import 'package:flutter/material.dart';
// import 'package:flutter_riverpod/flutter_riverpod.dart';
// import 'package:go_router/go_router.dart';

// import 'package:ngoda/data_models/currency/currency_balance.dart';
// import 'package:ngoda/data_models/wallet/wallet_balance_summary.dart';
// import 'package:ngoda/services/currency_service.dart';
// import 'package:ngoda/services/number_format_service.dart';
// import 'package:ngoda/ui/extensions/app_size.dart';
// import 'package:ngoda/ui/extensions/theme_extension.dart';
// import 'package:ngoda/ui/functions/get_current_user.dart';
// import 'package:ngoda/ui/screens/wallet/reports/provider/wallet_summary_provider.dart';
// import 'package:ngoda/ui/shared/app_text_styles.dart';
// import 'package:ngoda/ui/widgets/app_empty_state.dart';
// import 'package:ngoda/ui/widgets/app_error_state.dart';
// import 'package:ngoda/ui/widgets/app_loader.dart';
// import 'package:ngoda/ui/widgets/bottom_nav.dart';
// import 'package:ngoda/ui/widgets/screen_header.dart';
// import 'package:ngoda/ui/widgets/view_header.dart';

// class WalletBalanceSummaryScreen extends ConsumerWidget {
//   const WalletBalanceSummaryScreen({super.key});

//   @override
//   Widget build(BuildContext context, WidgetRef ref) {
//     final walletSummary = ref.watch(walletSummaryProvider);

//     final user = getCurrentUser();
//     final role = user.role;

//     final showBottomNav = role != 'customer';

//     final header = role == 'customer'
//         ? ViewHeader(
//             title: 'Wallet Balance Summary',
//             onClose: () {
//               ref.invalidate(walletSummaryProvider);

//               context.pop();
//             },
//           )
//         : const ScreenHeader(title: 'Wallet Balance Summary');

//     return Scaffold(
//       bottomNavigationBar: showBottomNav
//           ? const BottomNav(currentIndex: 2)
//           : null,
//       body: SafeArea(
//         child: Column(
//           children: [
//             header,

//             Expanded(
//               child: RefreshIndicator(
//                 onRefresh: () => _refresh(ref),
//                 child: walletSummary.when(
//                   loading: () => const AppLoader(
//                     message: 'Loading wallet summary',
//                     fullScreen: true,
//                   ),
//                   error: (error, _) =>
//                       _RefreshableError(message: error.toString()),
//                   data: (response) {
//                     if (response.error != null) {
//                       return _RefreshableError(
//                         message: response.error.toString(),
//                       );
//                     }

//                     final summary = response.result;

//                     if (summary == null || summary.sortedCurrencyList.isEmpty) {
//                       return const _RefreshableEmpty();
//                     }

//                     return _WalletSummaryContent(summary: summary);
//                   },
//                 ),
//               ),
//             ),
//           ],
//         ),
//       ),
//     );
//   }

//   Future<void> _refresh(WidgetRef ref) async {
//     ref.invalidate(walletSummaryProvider);

//     await ref.read(walletSummaryProvider.future);
//   }
// }

// class _WalletSummaryContent extends StatelessWidget {
//   const _WalletSummaryContent({required this.summary});

//   final WalletBalanceSummary summary;

//   @override
//   Widget build(BuildContext context) {
//     final spacing = context.spacing;

//     final user = getCurrentUser();

//     /*
//      * Preserve the existing navigation
//      * contract.
//      *
//      * We will review the receiving route
//      * when we clean the next report screen.
//      */
//     final path = user.role == 'treasury'
//         ? '/treasury-wallet/treasury/'
//         : '/customer-wallet/customer/';

//     final currencies = summary.sortedCurrencyList;

//     return ListView(
//       physics: const AlwaysScrollableScrollPhysics(),
//       padding: EdgeInsets.fromLTRB(
//         spacing.md,
//         spacing.sm,
//         spacing.md,
//         spacing.lg,
//       ),
//       children: [
//         _TotalBalanceCard(totalBalance: summary.totalUsdValue),

//         SizedBox(height: spacing.lg),

//         const _SectionHeader(
//           title: 'Balance breakdown',
//           description: 'Your available wallet balances by currency.',
//         ),

//         SizedBox(height: spacing.sm),

//         for (var index = 0; index < currencies.length; index++) ...[
//           _buildCurrencyCard(
//             context: context,
//             currencyCode: currencies[index],
//             path: path,
//           ),

//           if (index < currencies.length - 1) SizedBox(height: spacing.sm),
//         ],
//       ],
//     );
//   }

//   Widget _buildCurrencyCard({
//     required BuildContext context,
//     required String currencyCode,
//     required String path,
//   }) {
//     final balance = summary.walletBalances.getByCurrency(currencyCode);

//     if (balance == null) {
//       return const SizedBox.shrink();
//     }

//     return _CurrencyBalanceCard(
//       currencyCode: currencyCode,
//       balance: balance,
//       onTap: () {
//         context.push('$path${currencyCode.toLowerCase()}');
//       },
//     );
//   }
// }

// class _SectionHeader extends StatelessWidget {
//   const _SectionHeader({required this.title, required this.description});

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
//           style: AppTextStyles.medium(
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

// class _TotalBalanceCard extends StatelessWidget {
//   const _TotalBalanceCard({required this.totalBalance});

//   final double totalBalance;

//   static const Color _gold = Color(0xFFD4AF37);

//   @override
//   Widget build(BuildContext context) {
//     final spacing = context.spacing;
//     final iconSize = context.iconSize;
//     final colorScheme = context.colorScheme;

//     return Container(
//       width: double.infinity,
//       padding: EdgeInsets.all(spacing.lg),
//       decoration: BoxDecoration(
//         color: colorScheme.surfaceContainer,
//         borderRadius: BorderRadius.circular(spacing.md),
//         border: Border.all(color: _gold.withValues(alpha: 0.30)),
//       ),
//       child: Column(
//         crossAxisAlignment: CrossAxisAlignment.start,
//         children: [
//           Row(
//             children: [
//               Container(
//                 padding: EdgeInsets.all(spacing.sm),
//                 decoration: BoxDecoration(
//                   color: _gold.withValues(alpha: 0.12),
//                   shape: BoxShape.circle,
//                 ),
//                 child: Icon(
//                   Icons.account_balance_wallet_outlined,
//                   color: _gold,
//                   size: iconSize.large,
//                 ),
//               ),

//               SizedBox(width: spacing.sm),

//               Expanded(
//                 child: Column(
//                   crossAxisAlignment: CrossAxisAlignment.start,
//                   children: [
//                     Text(
//                       'Total wallet balance',
//                       style: AppTextStyles.small(
//                         context,
//                       ).copyWith(fontWeight: FontWeight.w600),
//                     ),

//                     SizedBox(height: spacing.xs),

//                     Text(
//                       'USD equivalent across all currencies',
//                       style: AppTextStyles.tiny(
//                         context,
//                       ).copyWith(color: colorScheme.onSurfaceVariant),
//                     ),
//                   ],
//                 ),
//               ),
//             ],
//           ),

//           SizedBox(height: spacing.lg),

//           Text(
//             NumberFormatService.formatAmount(totalBalance, currency: 'usd'),
//             style: AppTextStyles.mediumNumber(context),
//           ),
//         ],
//       ),
//     );
//   }
// }

// class _CurrencyBalanceCard extends StatelessWidget {
//   const _CurrencyBalanceCard({
//     required this.balance,
//     required this.currencyCode,
//     required this.onTap,
//   });

//   final CurrencyBalance balance;
//   final String currencyCode;
//   final VoidCallback onTap;

//   @override
//   Widget build(BuildContext context) {
//     final spacing = context.spacing;
//     final radius = context.radius;
//     final colorScheme = context.colorScheme;

//     final currencyName = CurrencyService.name(currencyCode);

//     final currencySymbol = CurrencyService.symbol(currencyCode);

//     return Material(
//       color: colorScheme.surfaceContainer,
//       shape: RoundedRectangleBorder(
//         borderRadius: BorderRadius.circular(radius.cardRadius),
//         side: BorderSide(
//           color: colorScheme.outlineVariant.withValues(alpha: 0.09),
//         ),
//       ),
//       clipBehavior: Clip.antiAlias,
//       child: InkWell(
//         onTap: onTap,
//         borderRadius: BorderRadius.circular(radius.cardRadius),
//         child: Padding(
//           padding: EdgeInsets.all(spacing.md),
//           child: Row(
//             children: [
//               _CurrencyIcon(code: currencyCode, symbol: currencySymbol),

//               SizedBox(width: spacing.md),

//               Expanded(
//                 child: Column(
//                   crossAxisAlignment: CrossAxisAlignment.start,
//                   children: [
//                     Text(
//                       currencyName,
//                       maxLines: 1,
//                       overflow: TextOverflow.ellipsis,
//                       style: AppTextStyles.small(
//                         context,
//                       ).copyWith(fontWeight: FontWeight.w600),
//                     ),

//                     SizedBox(height: spacing.xs),

//                     Text(
//                       currencyCode.toUpperCase(),
//                       style: AppTextStyles.tiny(
//                         context,
//                       ).copyWith(color: colorScheme.onSurfaceVariant),
//                     ),
//                   ],
//                 ),
//               ),

//               SizedBox(width: spacing.sm),

//               Column(
//                 crossAxisAlignment: CrossAxisAlignment.end,
//                 children: [
//                   Text(
//                     NumberFormatService.formatAmount(
//                       balance.balance,
//                       currency: currencyCode,
//                     ),
//                     style: AppTextStyles.smallNumber(context),
//                   ),

//                   SizedBox(height: spacing.xs),

//                   Text(
//                     NumberFormatService.formatAmount(
//                       balance.usdValue,
//                       currency: 'usd',
//                     ),
//                     style: AppTextStyles.tinyNumber(
//                       context,
//                     ).copyWith(color: colorScheme.onSurfaceVariant),
//                   ),
//                 ],
//               ),

//               SizedBox(width: spacing.sm),

//               Icon(
//                 Icons.chevron_right_rounded,
//                 color: colorScheme.onSurfaceVariant,
//               ),
//             ],
//           ),
//         ),
//       ),
//     );
//   }
// }

// class _CurrencyIcon extends StatelessWidget {
//   const _CurrencyIcon({required this.code, required this.symbol});

//   final String code;
//   final String symbol;

//   static const Color _gold = Color(0xFFD4AF37);

//   @override
//   Widget build(BuildContext context) {
//     final spacing = context.spacing;

//     final fallback = code.isEmpty
//         ? '?'
//         : code.substring(0, code.length >= 2 ? 2 : code.length).toUpperCase();

//     return Container(
//       width: spacing.xxxl,
//       height: spacing.xxxl,
//       alignment: Alignment.center,
//       decoration: BoxDecoration(
//         color: _gold.withValues(alpha: 0.12),
//         shape: BoxShape.circle,
//         border: Border.all(color: _gold.withValues(alpha: 0.25)),
//       ),
//       child: Text(
//         symbol.isNotEmpty ? symbol : fallback,
//         style: symbol == 'GOLD'
//             ? AppTextStyles.tiny(
//                 context,
//               ).copyWith(color: _gold, fontWeight: FontWeight.w700)
//             : AppTextStyles.small(
//                 context,
//               ).copyWith(color: _gold, fontWeight: FontWeight.w700),
//       ),
//     );
//   }
// }

// class _RefreshableError extends StatelessWidget {
//   const _RefreshableError({required this.message});

//   final String message;

//   @override
//   Widget build(BuildContext context) {
//     return ListView(
//       physics: const AlwaysScrollableScrollPhysics(),
//       children: [
//         SizedBox(
//           height: MediaQuery.sizeOf(context).height * 0.65,
//           child: AppErrorState(message: message),
//         ),
//       ],
//     );
//   }
// }

// class _RefreshableEmpty extends StatelessWidget {
//   const _RefreshableEmpty();

//   @override
//   Widget build(BuildContext context) {
//     return ListView(
//       physics: const AlwaysScrollableScrollPhysics(),
//       children: [
//         SizedBox(
//           height: MediaQuery.sizeOf(context).height * 0.65,
//           child: const AppEmptyState(),
//         ),
//       ],
//     );
//   }
// }
