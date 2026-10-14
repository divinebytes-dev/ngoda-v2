import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:ngoda/data_models/merchant/credit_agent_balance_report.dart';
import 'package:ngoda/data_models/params/credit_agent_balance_params.dart';
import 'package:ngoda/services/number_format_service.dart';
import 'package:ngoda/ui/extensions/app_size.dart';
import 'package:ngoda/ui/extensions/theme_extension.dart';
import 'package:ngoda/ui/screens/wallet/reports/provider/credit_agent_balance_provider.dart';
import 'package:ngoda/ui/shared/app_colors.dart';
import 'package:ngoda/ui/shared/app_text_styles.dart';
import 'package:ngoda/ui/widgets/app_empty_state.dart';
import 'package:ngoda/ui/widgets/app_error_state.dart';
import 'package:ngoda/ui/widgets/app_loader.dart';
import 'package:ngoda/ui/widgets/app_pagination.dart';
import 'package:ngoda/ui/widgets/view_header.dart';

class CreditAgentsBalanceScreen extends ConsumerStatefulWidget {
  const CreditAgentsBalanceScreen({super.key});

  @override
  ConsumerState<CreditAgentsBalanceScreen> createState() =>
      _CreditAgentBalanceScreenState();
}

class _CreditAgentBalanceScreenState
    extends ConsumerState<CreditAgentsBalanceScreen> {
  late CreditAgentBalanceParams params;

  late int currentPage;
  late int pageSize;

  String? selectedCurrency;

  @override
  void initState() {
    super.initState();

    params = CreditAgentBalanceParams(page: 1, pageSize: 50);

    currentPage = params.page;
    pageSize = params.pageSize;
  }

  CreditAgentBalanceParams get currentParams {
    return params.copyWith(page: currentPage, pageSize: pageSize);
  }

  Future<void> _refresh() async {
    ref.invalidate(creditAgentBalanceProvider(currentParams));

    await ref.read(creditAgentBalanceProvider(currentParams).future);
  }

  void _previousPage() {
    if (currentPage <= 1) {
      return;
    }

    setState(() {
      currentPage--;
    });
  }

  void _nextPage() {
    setState(() {
      currentPage++;
    });
  }

  void _changePageSize(int newPageSize) {
    if (newPageSize == pageSize) {
      return;
    }

    setState(() {
      pageSize = newPageSize;
      currentPage = 1;
    });
  }

  void _changeCurrency(String currency) {
    setState(() {
      selectedCurrency = currency.toLowerCase();
    });
  }

  void _closeScreen() {
    ref.invalidate(creditAgentBalanceProvider(currentParams));

    context.pop();
  }

  @override
  Widget build(BuildContext context) {
    final reportAsync = ref.watch(creditAgentBalanceProvider(currentParams));

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            ViewHeader(title: 'Credit Agent Balances', onClose: _closeScreen),
            Expanded(
              child: RefreshIndicator(
                onRefresh: _refresh,
                child: reportAsync.when(
                  loading: () => const AppLoader(
                    message: 'Loading credit agent balances',
                    fullScreen: false,
                  ),
                  error: (error, stackTrace) {
                    return _RefreshableState(
                      child: AppErrorState(message: error.toString()),
                    );
                  },
                  data: (response) {
                    if (response.error != null) {
                      return _RefreshableState(
                        child: AppErrorState(
                          message: response.error.toString(),
                        ),
                      );
                    }

                    final report = response.result;

                    if (report == null || report.creditAgents.isEmpty) {
                      return const _RefreshableState(child: AppEmptyState());
                    }

                    return _CreditAgentBalanceContent(
                      report: report,
                      selectedCurrency: selectedCurrency,
                      pageSize: pageSize,
                      onCurrencyChanged: _changeCurrency,
                      onPrevious: _previousPage,
                      onNext: _nextPage,
                      onPageSizeChanged: _changePageSize,
                    );
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

class _CreditAgentBalanceContent extends StatelessWidget {
  const _CreditAgentBalanceContent({
    required this.report,
    required this.selectedCurrency,
    required this.pageSize,
    required this.onCurrencyChanged,
    required this.onPrevious,
    required this.onNext,
    required this.onPageSizeChanged,
  });

  final CreditAgentBalanceReport report;
  final String? selectedCurrency;
  final int pageSize;

  final ValueChanged<String> onCurrencyChanged;

  final VoidCallback onPrevious;
  final VoidCallback onNext;

  final ValueChanged<int> onPageSizeChanged;

  List<String> get currencies {
    final result = <String>{};

    for (final merchant in report.creditAgents) {
      result.addAll(
        merchant.creditAgentWallet.currencies.keys.map(
          (currency) => currency.toLowerCase(),
        ),
      );
    }

    final values = result.toList();

    values.sort();

    return values;
  }

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;

    final availableCurrencies = currencies;

    if (availableCurrencies.isEmpty) {
      return const _RefreshableState(child: AppEmptyState());
    }

    final normalizedSelected = selectedCurrency?.toLowerCase();

    final currency =
        normalizedSelected != null &&
            availableCurrencies.contains(normalizedSelected)
        ? normalizedSelected
        : availableCurrencies.first;

    final currencyMerchants = report.creditAgents
        .where((merchant) => merchant.creditAgentWallet[currency] != null)
        .toList();

    return Column(
      children: [
        _CurrencyTabsSelector(
          currencies: availableCurrencies,
          selectedCurrency: currency,
          onChanged: onCurrencyChanged,
        ),
        Expanded(
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: EdgeInsets.fromLTRB(spacing.sm, 0, spacing.sm, spacing.md),
            children: [
              _CurrencyTotalCard(
                merchants: currencyMerchants,
                currency: currency,
              ),
              SizedBox(height: spacing.lg),
              _SectionHeader(
                title: 'Credit Agents',
                trailing: currencyMerchants.length.toString(),
              ),
              SizedBox(height: spacing.sm),
              if (currencyMerchants.isEmpty)
                const _InlineEmptyState()
              else
                ...currencyMerchants.map((merchant) {
                  return Padding(
                    padding: EdgeInsets.only(bottom: spacing.sm),
                    child: _CreditAgentBalanceCard(
                      merchant: merchant,
                      currency: currency,
                      onTap: () {
                        context.push(
                          '/accounts-funding/credit-agents-balances/entries',
                          extra: CreditAgentBalanceParams(
                            merchantId: merchant.userId,
                            currency: currency,
                            page: 1,
                            pageSize: 50,
                          ),
                        );
                      },
                    ),
                  );
                }),
            ],
          ),
        ),
        AppPagination(
          page: report.pagination.page,
          totalPages: report.pagination.totalPages,
          totalEntries: report.pagination.totalEntries,
          hasPrevious: report.pagination.hasPrevious,
          hasNext: report.pagination.hasNext,
          onPrevious: onPrevious,
          onNext: onNext,
          pageSize: pageSize,
          onPageSizeChanged: onPageSizeChanged,
          entryLabel: 'credit agents',
        ),
      ],
    );
  }
}

class _CurrencyTabsSelector extends StatelessWidget {
  const _CurrencyTabsSelector({
    required this.currencies,
    required this.selectedCurrency,
    required this.onChanged,
  });

  final List<String> currencies;
  final String selectedCurrency;

  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;

    return Padding(
      padding: EdgeInsets.fromLTRB(
        spacing.sm,
        spacing.xs,
        spacing.sm,
        spacing.sm,
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: currencies.map((currency) {
            final isSelected =
                currency.toLowerCase() == selectedCurrency.toLowerCase();

            return Padding(
              padding: EdgeInsets.only(right: spacing.sm),
              child: _CurrencyTab(
                currency: currency.toUpperCase(),
                selected: isSelected,
                onTap: () {
                  onChanged(currency.toLowerCase());
                },
              ),
            );
          }).toList(),
        ),
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

    final theme = Theme.of(context);

    final primary = theme.colorScheme.primary;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(radius.sm),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: EdgeInsets.symmetric(
            horizontal: spacing.md,
            vertical: spacing.sm,
          ),
          decoration: BoxDecoration(
            color: selected
                ? primary.withValues(alpha: 0.12)
                : AppColors.darkCard,
            borderRadius: BorderRadius.circular(radius.sm),
            border: Border.all(
              color: selected ? primary : AppColors.darkBorder,
            ),
          ),
          child: Text(
            currency,
            style: AppTextStyles.small(context).copyWith(
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              color: selected ? primary : null,
            ),
          ),
        ),
      ),
    );
  }
}

class _CurrencyTotalCard extends StatelessWidget {
  const _CurrencyTotalCard({required this.merchants, required this.currency});

  final List<CreditAgentBalanceMerchant> merchants;

  final String currency;

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    final radius = context.radius;

    double cashOwed = 0;
    double receivable = 0;

    for (final merchant in merchants) {
      final balance = merchant.creditAgentWallet[currency];

      if (balance == null) {
        continue;
      }

      cashOwed += balance.cashOwed.balance;

      receivable += balance.receivableBalance.balance;
    }

    final outstanding = cashOwed + receivable;

    return Container(
      padding: EdgeInsets.all(spacing.xs),
      decoration: BoxDecoration(
        color: AppColors.darkCard,
        borderRadius: BorderRadius.circular(radius.md),
      ),
      child: Container(
        width: double.infinity,
        padding: EdgeInsets.all(spacing.md),
        decoration: BoxDecoration(
          color: Theme.of(context).scaffoldBackgroundColor,
          borderRadius: BorderRadius.circular(radius.sm),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${currency.toUpperCase()} Balance Summary',
              style: AppTextStyles.small(
                context,
              ).copyWith(fontWeight: FontWeight.w700),
            ),
            SizedBox(height: spacing.xs),
            Text(
              NumberFormatService.formatAmount(outstanding, currency: currency),
              style: AppTextStyles.largeNumber(
                context,
              ).copyWith(fontWeight: FontWeight.w800),
            ),
            SizedBox(height: spacing.md),
            Divider(height: 1, color: AppColors.darkBorder),
            SizedBox(height: spacing.sm),
            _SummaryRow(
              label: 'Cash Owed',
              value: cashOwed,
              currency: currency,
              valueColor: Colors.red,
            ),
            SizedBox(height: spacing.sm),
            _SummaryRow(
              label: 'Receivable',
              value: receivable,
              currency: currency,
              valueColor: Colors.green,
            ),
          ],
        ),
      ),
    );
  }
}

class _CreditAgentBalanceCard extends StatelessWidget {
  const _CreditAgentBalanceCard({
    required this.merchant,
    required this.currency,
    this.onTap,
  });

  final CreditAgentBalanceMerchant merchant;

  final String currency;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    final radius = context.radius;
    final iconSize = context.iconSize;
    final colorScheme = context.colorScheme;

    final balance = merchant.creditAgentWallet[currency];

    final cashOwed = balance?.cashOwed.balance ?? 0;

    final cashOwedUsd = balance?.cashOwed.usdValue ?? 0;

    final receivable = balance?.receivableBalance.balance ?? 0;

    final receivableUsd = balance?.receivableBalance.usdValue ?? 0;

    return Material(
      color: AppColors.darkCard,
      borderRadius: BorderRadius.circular(radius.md),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(radius.md),
        child: Padding(
          padding: EdgeInsets.all(spacing.md),
          child: Column(
            children: [
              Row(
                children: [
                  _MerchantIcon(isActive: merchant.isActive),
                  SizedBox(width: spacing.sm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          merchant.displayName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTextStyles.small(
                            context,
                          ).copyWith(fontWeight: FontWeight.w700),
                        ),
                        if (merchant.contact.isNotEmpty) ...[
                          SizedBox(height: spacing.xs),
                          Text(
                            merchant.contact,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTextStyles.tiny(
                              context,
                            ).copyWith(color: colorScheme.onSurfaceVariant),
                          ),
                        ],
                      ],
                    ),
                  ),
                  SizedBox(width: spacing.sm),
                  _CurrencyBadge(currency: currency),
                  if (onTap != null) ...[
                    SizedBox(width: spacing.xs),
                    Icon(
                      Icons.chevron_right_rounded,
                      size: iconSize.small,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ],
                ],
              ),
              SizedBox(height: spacing.sm),
              Divider(height: 1, color: AppColors.darkBorder),
              SizedBox(height: spacing.sm),
              _BalanceRow(
                label: 'Cash Owed',
                amount: cashOwed,
                usdValue: cashOwedUsd,
                currency: currency,
                color: Colors.red,
              ),
              SizedBox(height: spacing.sm),
              _BalanceRow(
                label: 'Receivable',
                amount: receivable,
                usdValue: receivableUsd,
                currency: currency,
                color: Colors.green,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MerchantIcon extends StatelessWidget {
  const _MerchantIcon({required this.isActive});

  final bool isActive;

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    final iconSize = context.iconSize;

    final color = isActive
        ? Theme.of(context).colorScheme.primary
        : AppColors.darkBorder;

    return Container(
      width: spacing.xl,
      height: spacing.xl,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        shape: BoxShape.circle,
      ),
      child: Icon(Icons.store_outlined, size: iconSize.small, color: color),
    );
  }
}

class _CurrencyBadge extends StatelessWidget {
  const _CurrencyBadge({required this.currency});

  final String currency;

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    final radius = context.radius;

    final primary = Theme.of(context).colorScheme.primary;

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: spacing.sm,
        vertical: spacing.xs,
      ),
      decoration: BoxDecoration(
        color: primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(radius.sm),
      ),
      child: Text(
        currency.toUpperCase(),
        style: AppTextStyles.tiny(
          context,
        ).copyWith(color: primary, fontWeight: FontWeight.w700),
      ),
    );
  }
}

class _BalanceRow extends StatelessWidget {
  const _BalanceRow({
    required this.label,
    required this.amount,
    required this.usdValue,
    required this.currency,
    required this.color,
  });

  final String label;
  final double amount;
  final double usdValue;
  final String currency;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    final colorScheme = context.colorScheme;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Text(
            label,
            style: AppTextStyles.tiny(context).copyWith(
              color: colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              NumberFormatService.formatAmount(amount, currency: currency),
              style: AppTextStyles.smallNumber(
                context,
              ).copyWith(color: color, fontWeight: FontWeight.w700),
            ),
            if (currency.toLowerCase() != 'usd') ...[
              SizedBox(height: spacing.xs),
              Text(
                '≈ ${NumberFormatService.formatUsd(usdValue)}',
                style: AppTextStyles.tinyNumber(
                  context,
                ).copyWith(color: colorScheme.onSurfaceVariant),
              ),
            ],
          ],
        ),
      ],
    );
  }
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({
    required this.label,
    required this.value,
    required this.currency,
    this.valueColor,
  });

  final String label;
  final double value;
  final String currency;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: AppTextStyles.tiny(context).copyWith(
            color: colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w600,
          ),
        ),
        Text(
          NumberFormatService.formatAmount(value, currency: currency),
          style: AppTextStyles.smallNumber(
            context,
          ).copyWith(color: valueColor, fontWeight: FontWeight.w700),
        ),
      ],
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, required this.trailing});

  final String title;
  final String trailing;

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    final radius = context.radius;

    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: AppTextStyles.small(
              context,
            ).copyWith(fontWeight: FontWeight.w700),
          ),
        ),
        Container(
          padding: EdgeInsets.symmetric(
            horizontal: spacing.sm,
            vertical: spacing.xs,
          ),
          decoration: BoxDecoration(
            color: AppColors.darkCard,
            borderRadius: BorderRadius.circular(radius.sm),
          ),
          child: Text(
            trailing,
            style: AppTextStyles.tinyNumber(
              context,
            ).copyWith(fontWeight: FontWeight.w700),
          ),
        ),
      ],
    );
  }
}

class _InlineEmptyState extends StatelessWidget {
  const _InlineEmptyState();

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;

    return Padding(
      padding: EdgeInsets.symmetric(vertical: spacing.xl),
      child: const AppEmptyState(),
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
          child: Center(child: child),
        ),
      ],
    );
  }
}
