import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:ngoda/data_models/admin/admin_dashboard.dart';
import 'package:ngoda/data_models/admin/operational_country.dart';
import 'package:ngoda/data_models/admin/user_role.dart';
import 'package:ngoda/data_models/currency/currency.dart';
import 'package:ngoda/ui/extensions/app_size.dart';
import 'package:ngoda/ui/functions/is_jwt_expired.dart';
import 'package:ngoda/ui/screens/admin/provider/admin_dashboard_provider.dart';
import 'package:ngoda/ui/screens/auth/providers/auth_provider.dart';
import 'package:ngoda/ui/shared/app_text_styles.dart';
import 'package:ngoda/ui/shared/theme_provider.dart';
import 'package:ngoda/ui/widgets/app_empty_state.dart';
import 'package:ngoda/ui/widgets/app_error_state.dart';
import 'package:ngoda/ui/widgets/app_loader.dart';
import 'package:ngoda/ui/widgets/bottom_nav.dart';

class AdminDashboardScreen extends ConsumerStatefulWidget {
  const AdminDashboardScreen({super.key});

  @override
  ConsumerState<AdminDashboardScreen> createState() =>
      _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends ConsumerState<AdminDashboardScreen> {
  String? selectedCountryCode;

  Future<void> _refresh() async {
    ref.invalidate(adminDashboardProvider);

    await ref.read(adminDashboardProvider.future);
  }

  void _changeCountry(String countryCode) {
    setState(() {
      selectedCountryCode = countryCode.toLowerCase();
    });
  }

  Future<void> _logout() async {
    await ref.read(authProvider.notifier).logout('Session Expired');

    if (!mounted) {
      return;
    }

    context.go('/login');
  }

  @override
  Widget build(BuildContext context) {
    final asyncData = ref.watch(adminDashboardProvider);

    return asyncData.when(
      loading: () {
        return const AppLoader(message: 'Loading dashboard', fullScreen: true);
      },
      error: (error, stackTrace) {
        return _buildErrorState(error.toString());
      },
      data: (response) {
        if (response.error != null) {
          return _buildErrorState(response.error!);
        }

        final dashboard = response.result;

        if (dashboard == null) {
          return const Scaffold(body: AppEmptyState());
        }

        return _buildDashboard(dashboard);
      },
    );
  }

  Widget _buildErrorState(String error) {
    if (isJwtExpired(error)) {
      return Scaffold(
        body: SafeArea(
          child: AppErrorState(
            title: 'Session Expired',
            message: 'Please login again to continue.',
            buttonText: 'Logout',
            onAction: _logout,
          ),
        ),
      );
    }

    return Scaffold(
      body: SafeArea(
        child: AppErrorState(
          message: error,
          buttonText: 'Retry',
          onAction: _refresh,
        ),
      ),
    );
  }

  Widget _buildDashboard(AdminDashboard dashboard) {
    final spacing = context.spacing;

    final operationalCountries = dashboard.operationalCountries;

    final selectedCode = _resolveSelectedCountry(operationalCountries);

    final selectedOperationalCountry = _findOperationalCountry(
      dashboard,
      selectedCode,
    );

    final selectedCountrySummary = _findCountrySummary(dashboard, selectedCode);

    return Scaffold(
      bottomNavigationBar: const BottomNav(currentIndex: 0),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _refresh,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: EdgeInsets.fromLTRB(
              spacing.md,
              spacing.sm,
              spacing.md,
              spacing.lg,
            ),
            children: [
              SizedBox(height: spacing.md),

              const _TopBar(),

              SizedBox(height: spacing.xs),

              Text(
                'System Administration',
                style: AppTextStyles.small(context).copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),

              SizedBox(height: spacing.md),

              _UserSummaryCard(
                summary: dashboard.summary,
                roles: dashboard.roles,
              ),

              SizedBox(height: spacing.lg),

              if (operationalCountries.isNotEmpty) ...[
                _SectionHeader(
                  title: 'Operational Countries',
                  trailing: operationalCountries.length.toString(),
                ),

                SizedBox(height: spacing.sm),

                _CountryTabs(
                  countries: operationalCountries,
                  selectedCountryCode: selectedCode,
                  onChanged: _changeCountry,
                ),

                SizedBox(height: spacing.md),

                if (selectedOperationalCountry != null)
                  _OperationalCountryCard(country: selectedOperationalCountry),

                if (selectedOperationalCountry != null)
                  SizedBox(height: spacing.lg),

                if (selectedCountrySummary != null) ...[
                  _CountryUserSummaryCard(
                    country: selectedCountrySummary,
                    roles: dashboard.roles,
                  ),

                  SizedBox(height: spacing.lg),
                ],

                if (selectedOperationalCountry != null) ...[
                  _SectionHeader(
                    title: 'Currencies',
                    trailing: selectedOperationalCountry.currencies.length
                        .toString(),
                  ),

                  SizedBox(height: spacing.sm),

                  if (selectedOperationalCountry.currencies.isEmpty)
                    const AppEmptyState()
                  else
                    ...selectedOperationalCountry.currencies.map((currency) {
                      return Padding(
                        padding: EdgeInsets.only(bottom: spacing.sm),
                        child: _CurrencyCard(currency: currency),
                      );
                    }),
                ],
              ] else
                const AppEmptyState(),
            ],
          ),
        ),
      ),
    );
  }

  String _resolveSelectedCountry(List<OperationalCountry> countries) {
    if (countries.isEmpty) {
      return '';
    }

    final normalized = selectedCountryCode?.toLowerCase();

    if (normalized != null &&
        countries.any(
          (country) => country.countryCode.toLowerCase() == normalized,
        )) {
      return normalized;
    }

    return countries.first.countryCode.toLowerCase();
  }

  OperationalCountry? _findOperationalCountry(
    AdminDashboard dashboard,
    String countryCode,
  ) {
    for (final country in dashboard.operationalCountries) {
      if (country.countryCode.toLowerCase() == countryCode.toLowerCase()) {
        return country;
      }
    }

    return null;
  }

  AdminCountrySummary? _findCountrySummary(
    AdminDashboard dashboard,
    String countryCode,
  ) {
    for (final country in dashboard.countries) {
      if (country.countryCode.toLowerCase() == countryCode.toLowerCase()) {
        return country;
      }
    }

    return null;
  }
}

class _TopBar extends ConsumerWidget {
  const _TopBar();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(themeModeProvider);

    final colorScheme = Theme.of(context).colorScheme;

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(
          child: Text(
            'Welcome Back',
            style: AppTextStyles.large(
              context,
            ).copyWith(fontWeight: FontWeight.w700),
          ),
        ),

        IconButton(
          tooltip: mode == ThemeMode.dark ? 'Light mode' : 'Dark mode',
          icon: Icon(
            mode == ThemeMode.dark
                ? Icons.light_mode_outlined
                : Icons.dark_mode_outlined,
            color: colorScheme.primary,
          ),
          onPressed: () {
            ref.read(themeModeProvider.notifier).toggle();
          },
        ),
      ],
    );
  }
}

class _UserSummaryCard extends StatelessWidget {
  final AdminDashboardTotals summary;
  final List<UserRole> roles;

  const _UserSummaryCard({required this.summary, required this.roles});

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    final colorScheme = Theme.of(context).colorScheme;

    return _DashboardCard(
      child: Column(
        children: [
          const _CardTitle(
            title: 'System Users',
            icon: Icons.groups_2_outlined,
          ),

          SizedBox(height: spacing.md),

          Divider(height: 1, color: colorScheme.outlineVariant),

          SizedBox(height: spacing.md),

          _SummaryRow(
            label: 'Total Users',
            value: summary.totalUsers,
            strong: true,
          ),

          SizedBox(height: spacing.sm),

          _SummaryRow(
            label: 'Credit Agents',
            value: summary.creditAgents,
            valueColor: colorScheme.tertiary,
          ),

          SizedBox(height: spacing.md),

          Divider(height: 1, color: colorScheme.outlineVariant),

          SizedBox(height: spacing.md),

          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'Users by Role',
              style: AppTextStyles.tiny(context).copyWith(
                color: colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),

          SizedBox(height: spacing.sm),

          ...roles.map((role) {
            return Padding(
              padding: EdgeInsets.only(bottom: spacing.sm),
              child: _SummaryRow(
                label: _formatRole(role.name),
                value: summary.roleCount(role.name),
              ),
            );
          }),
        ],
      ),
    );
  }
}

class _CountryUserSummaryCard extends StatelessWidget {
  final AdminCountrySummary country;
  final List<UserRole> roles;

  const _CountryUserSummaryCard({required this.country, required this.roles});

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    final colorScheme = Theme.of(context).colorScheme;

    return _DashboardCard(
      child: Column(
        children: [
          _CardTitle(
            title: '${country.countryCode.toUpperCase()} Users',
            icon: Icons.people_outline,
          ),

          SizedBox(height: spacing.md),

          _SummaryRow(
            label: 'Total Users',
            value: country.totalUsers,
            strong: true,
          ),

          SizedBox(height: spacing.sm),

          _SummaryRow(
            label: 'Credit Agents',
            value: country.creditAgents,
            valueColor: colorScheme.tertiary,
          ),

          SizedBox(height: spacing.md),

          Divider(height: 1, color: colorScheme.outlineVariant),

          SizedBox(height: spacing.md),

          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'Users by Role',
              style: AppTextStyles.tiny(context).copyWith(
                color: colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),

          SizedBox(height: spacing.sm),

          ...roles.map((role) {
            return Padding(
              padding: EdgeInsets.only(bottom: spacing.sm),
              child: _SummaryRow(
                label: _formatRole(role.name),
                value: country.roleCount(role.name),
              ),
            );
          }),
        ],
      ),
    );
  }
}

class _CountryTabs extends StatelessWidget {
  final List<OperationalCountry> countries;

  final String selectedCountryCode;

  final ValueChanged<String> onChanged;

  const _CountryTabs({
    required this.countries,
    required this.selectedCountryCode,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: countries.map((country) {
          final selected =
              country.countryCode.toLowerCase() ==
              selectedCountryCode.toLowerCase();

          return Padding(
            padding: EdgeInsets.only(right: spacing.sm),
            child: _CountryTab(
              country: country,
              selected: selected,
              onTap: () {
                onChanged(country.countryCode);
              },
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _CountryTab extends StatelessWidget {
  final OperationalCountry country;
  final bool selected;
  final VoidCallback onTap;

  const _CountryTab({
    required this.country,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    final radius = context.radius;
    final colorScheme = Theme.of(context).colorScheme;

    final primary = colorScheme.primary;

    final statusColor = country.isActive
        ? Colors.green
        : colorScheme.onSurfaceVariant;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(radius.xl),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: EdgeInsets.symmetric(
            horizontal: spacing.md,
            vertical: spacing.sm,
          ),
          decoration: BoxDecoration(
            color: selected
                ? primary.withValues(alpha: 0.10)
                : colorScheme.surface,
            borderRadius: BorderRadius.circular(radius.xl),
            border: Border.all(
              color: selected ? primary : colorScheme.outlineVariant,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: spacing.sm,
                height: spacing.sm,
                decoration: BoxDecoration(
                  color: statusColor,
                  shape: BoxShape.circle,
                ),
              ),

              SizedBox(width: spacing.sm),

              Text(
                country.name,
                style: AppTextStyles.small(context).copyWith(
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  color: selected ? primary : colorScheme.onSurface,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _OperationalCountryCard extends StatelessWidget {
  final OperationalCountry country;

  const _OperationalCountryCard({required this.country});

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    final iconSize = context.iconSize;
    final colorScheme = Theme.of(context).colorScheme;

    return _DashboardCard(
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: iconSize.xl + spacing.md,
                height: iconSize.xl + spacing.md,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: colorScheme.primary.withValues(alpha: 0.10),
                  shape: BoxShape.circle,
                ),
                child: Text(
                  country.countryCode.toUpperCase(),
                  style: AppTextStyles.small(context).copyWith(
                    color: colorScheme.primary,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),

              SizedBox(width: spacing.md),

              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      country.name,
                      style: AppTextStyles.small(
                        context,
                      ).copyWith(fontWeight: FontWeight.w700),
                    ),

                    SizedBox(height: spacing.xs),

                    Text(
                      country.countryCode.toUpperCase(),
                      style: AppTextStyles.tiny(
                        context,
                      ).copyWith(color: colorScheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),

              _StatusBadge(active: country.isActive),
            ],
          ),

          SizedBox(height: spacing.md),

          Divider(height: 1, color: colorScheme.outlineVariant),

          SizedBox(height: spacing.md),

          _InfoRow(
            label: 'Currencies',
            value: country.currencies.length.toString(),
          ),
        ],
      ),
    );
  }
}

class _CurrencyCard extends StatelessWidget {
  final Currency currency;

  const _CurrencyCard({required this.currency});

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    final radius = context.radius;
    final iconSize = context.iconSize;
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      padding: EdgeInsets.all(spacing.md),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(radius.md),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Row(
        children: [
          Container(
            width: iconSize.xl + spacing.sm,
            height: iconSize.xl + spacing.sm,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: colorScheme.primary.withValues(alpha: 0.10),
              shape: BoxShape.circle,
            ),
            child: Text(
              currency.symbol.isNotEmpty
                  ? currency.symbol
                  : currency.code.toUpperCase(),
              style: AppTextStyles.small(context).copyWith(
                color: colorScheme.primary,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),

          SizedBox(width: spacing.md),

          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  currency.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.small(
                    context,
                  ).copyWith(fontWeight: FontWeight.w700),
                ),

                SizedBox(height: spacing.xs),

                Text(
                  '${currency.code.toUpperCase()}'
                  ' • ${currency.decimals} decimals',
                  style: AppTextStyles.tiny(
                    context,
                  ).copyWith(color: colorScheme.onSurfaceVariant),
                ),
              ],
            ),
          ),

          SizedBox(width: spacing.sm),

          _StatusBadge(active: currency.isActive),
        ],
      ),
    );
  }
}

class _DashboardCard extends StatelessWidget {
  final Widget child;

  const _DashboardCard({required this.child});

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    final radius = context.radius;
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(spacing.md),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(radius.lg),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: child,
    );
  }
}

class _CardTitle extends StatelessWidget {
  final String title;
  final IconData icon;

  const _CardTitle({required this.title, required this.icon});

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    final radius = context.radius;
    final iconSize = context.iconSize;
    final colorScheme = Theme.of(context).colorScheme;

    return Row(
      children: [
        Container(
          padding: EdgeInsets.all(spacing.sm),
          decoration: BoxDecoration(
            color: colorScheme.primary.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(radius.md),
          ),
          child: Icon(icon, color: colorScheme.primary, size: iconSize.medium),
        ),

        SizedBox(width: spacing.md),

        Expanded(
          child: Text(
            title,
            style: AppTextStyles.small(
              context,
            ).copyWith(fontWeight: FontWeight.w700),
          ),
        ),
      ],
    );
  }
}

class _SummaryRow extends StatelessWidget {
  final String label;
  final int value;
  final bool strong;
  final Color? valueColor;

  const _SummaryRow({
    required this.label,
    required this.value,
    this.strong = false,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    final colorScheme = Theme.of(context).colorScheme;

    final valueStyle = strong
        ? AppTextStyles.smallNumber(context)
        : AppTextStyles.tinyNumber(context);

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(
          child: Text(
            label,
            style: AppTextStyles.tiny(context).copyWith(
              color: colorScheme.onSurfaceVariant,
              fontWeight: strong ? FontWeight.w700 : FontWeight.w600,
            ),
          ),
        ),

        SizedBox(width: spacing.md),

        Text(
          value.toString(),
          style: valueStyle.copyWith(
            color: valueColor,
            fontWeight: strong ? FontWeight.w800 : FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;

  const _InfoRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    final colorScheme = Theme.of(context).colorScheme;

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
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

        SizedBox(width: spacing.md),

        Text(
          value,
          style: AppTextStyles.tinyNumber(
            context,
          ).copyWith(fontWeight: FontWeight.w700),
        ),
      ],
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final bool active;

  const _StatusBadge({required this.active});

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    final radius = context.radius;
    final colorScheme = Theme.of(context).colorScheme;

    final color = active ? Colors.green : colorScheme.onSurfaceVariant;

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: spacing.sm,
        vertical: spacing.xs,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(radius.xl),
      ),
      child: Text(
        active ? 'Active' : 'Inactive',
        style: AppTextStyles.tiny(
          context,
        ).copyWith(color: color, fontWeight: FontWeight.w700),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final String trailing;

  const _SectionHeader({required this.title, required this.trailing});

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    final radius = context.radius;
    final colorScheme = Theme.of(context).colorScheme;

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
            color: colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(radius.xl),
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

String _formatRole(String role) {
  if (role.isEmpty) {
    return role;
  }

  return role
      .split('_')
      .where((part) => part.isNotEmpty)
      .map(
        (part) =>
            '${part[0].toUpperCase()}'
            '${part.substring(1).toLowerCase()}',
      )
      .join(' ');
}
