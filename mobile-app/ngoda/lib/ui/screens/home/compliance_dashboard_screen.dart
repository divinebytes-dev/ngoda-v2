import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:ngoda/data_models/compliance/compliance_dashboard.dart';
import 'package:ngoda/data_models/kyc/kyc_country_summary.dart';
import 'package:ngoda/data_models/kyc/kyc_role_summary.dart';
import 'package:ngoda/data_models/kyc/kyc_summary.dart';
import 'package:ngoda/ui/extensions/app_size.dart';
import 'package:ngoda/ui/extensions/theme_extension.dart';
import 'package:ngoda/ui/functions/is_jwt_expired.dart';
import 'package:ngoda/ui/screens/auth/providers/auth_provider.dart';
import 'package:ngoda/ui/screens/compliance/providers/compliance_dashboard_provider.dart';
import 'package:ngoda/ui/shared/app_colors.dart';
import 'package:ngoda/ui/shared/app_text_styles.dart';
import 'package:ngoda/ui/shared/theme_provider.dart';
import 'package:ngoda/ui/widgets/app_error_state.dart';
import 'package:ngoda/ui/widgets/app_loader.dart';
import 'package:ngoda/ui/widgets/bottom_nav.dart';

class ComplianceDashboardScreen extends ConsumerStatefulWidget {
  const ComplianceDashboardScreen({super.key});

  @override
  ConsumerState<ComplianceDashboardScreen> createState() =>
      _ComplianceDashboardScreenState();
}

class _ComplianceDashboardScreenState
    extends ConsumerState<ComplianceDashboardScreen> {
  String? selectedCountryCode;

  @override
  Widget build(BuildContext context) {
    final asyncData = ref.watch(complianceDashboardProvider);

    return asyncData.when(
      loading: () => const AppLoader(
        message: 'Loading compliance dashboard',
        fullScreen: true,
      ),
      error: (error, _) {
        if (isJwtExpired(error)) {
          return _SessionExpired(
            onLogout: () async {
              await ref.read(authProvider.notifier).logout('Session Expired');

              if (!context.mounted) {
                return;
              }

              context.go('/login');
            },
          );
        }

        return Scaffold(body: AppErrorState(message: error.toString()));
      },
      data: (response) {
        if (response.error != null) {
          if (isJwtExpired(response.error!)) {
            return _SessionExpired(
              onLogout: () async {
                await ref.read(authProvider.notifier).logout('Session Expired');

                if (!context.mounted) {
                  return;
                }

                context.go('/login');
              },
            );
          }

          return Scaffold(
            body: AppErrorState(message: response.error.toString()),
          );
        }

        final dashboard = response.result;

        if (dashboard == null) {
          return const Scaffold(
            body: AppErrorState(
              message: 'Compliance dashboard is not available',
            ),
          );
        }

        return _buildDashboard(dashboard);
      },
    );
  }

  Widget _buildDashboard(ComplianceDashboard dashboard) {
    final spacing = context.spacing;

    final countries = dashboard.sortedCountries;

    final selectedCode = _resolveSelectedCountry(countries);

    final selectedCountry = selectedCode == null
        ? null
        : dashboard.country(selectedCode);

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
              const _DashboardHeader(),

              SizedBox(height: spacing.lg),

              _OverallKycCard(summary: dashboard.summary),

              if (dashboard.summary.sortedRoleCounts.isNotEmpty) ...[
                SizedBox(height: spacing.lg),

                _SectionHeader(
                  title: 'KYC by Role',
                  trailing: dashboard.summary.sortedRoleCounts.length
                      .toString(),
                ),

                SizedBox(height: spacing.sm),

                _RoleSummaryCard(roles: dashboard.summary.sortedRoleCounts),
              ],

              if (countries.isNotEmpty) ...[
                SizedBox(height: spacing.lg),

                _SectionHeader(
                  title: 'Countries',
                  trailing: dashboard.countryCount.toString(),
                ),

                SizedBox(height: spacing.sm),

                _CountryTabs(
                  countries: countries,
                  selectedCountryCode: selectedCode,
                  onChanged: _changeCountry,
                ),

                if (selectedCountry != null) ...[
                  SizedBox(height: spacing.md),

                  _CountrySummaryCard(country: selectedCountry),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }

  String? _resolveSelectedCountry(List<KycCountrySummary> countries) {
    if (countries.isEmpty) {
      return null;
    }

    final selected = selectedCountryCode?.trim().toLowerCase();

    if (selected != null &&
        countries.any(
          (country) => country.countryCode.toLowerCase() == selected,
        )) {
      return selected;
    }

    return countries.first.countryCode;
  }

  void _changeCountry(String countryCode) {
    setState(() {
      selectedCountryCode = countryCode.trim().toLowerCase();
    });
  }

  Future<void> _refresh() async {
    ref.invalidate(complianceDashboardProvider);

    await ref.read(complianceDashboardProvider.future);
  }
}

class _SessionExpired extends StatelessWidget {
  const _SessionExpired({required this.onLogout});

  final Future<void> Function() onLogout;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: AppErrorState(
        title: 'Session Expired',
        message: 'Please login again to continue.',
        buttonText: 'Logout',
        onAction: onLogout,
      ),
    );
  }
}

class _DashboardHeader extends ConsumerWidget {
  const _DashboardHeader();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final spacing = context.spacing;
    final colorScheme = context.colorScheme;

    final mode = ref.watch(themeModeProvider);

    return Padding(
      padding: EdgeInsets.only(top: spacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
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
                icon: Icon(
                  mode == ThemeMode.dark ? Icons.light_mode : Icons.dark_mode,
                ),
                onPressed: () {
                  ref.read(themeModeProvider.notifier).toggle();
                },
              ),
            ],
          ),

          SizedBox(height: spacing.xs),

          Text(
            'Compliance & KYC Overview',
            style: AppTextStyles.small(
              context,
            ).copyWith(color: colorScheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

class _OverallKycCard extends StatelessWidget {
  const _OverallKycCard({required this.summary});

  final KycSummary summary;

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    final radius = context.radius;
    final colorScheme = context.colorScheme;

    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(spacing.md),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(radius.borderRadius),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Overall KYC Status',
            style: AppTextStyles.medium(
              context,
            ).copyWith(fontWeight: FontWeight.w700),
          ),

          SizedBox(height: spacing.xs),

          Text(
            '${summary.totalUsers} total users',
            style: AppTextStyles.small(
              context,
            ).copyWith(color: colorScheme.onSurfaceVariant),
          ),

          SizedBox(height: spacing.lg),

          _MetricRow(
            label: 'Verified',
            value: summary.verified,
            total: summary.totalUsers,
            color: AppColors.success,
          ),

          SizedBox(height: spacing.md),

          _MetricRow(
            label: 'Pending Review',
            value: summary.pendingReview,
            total: summary.totalUsers,
            color: AppColors.warning,
          ),

          SizedBox(height: spacing.md),

          _MetricRow(
            label: 'Started',
            value: summary.started,
            total: summary.totalUsers,
            color: AppColors.info,
          ),

          SizedBox(height: spacing.md),

          _MetricRow(
            label: 'Not Started',
            value: summary.notStarted,
            total: summary.totalUsers,
            color: colorScheme.onSurfaceVariant,
          ),
        ],
      ),
    );
  }
}

class _MetricRow extends StatelessWidget {
  const _MetricRow({
    required this.label,
    required this.value,
    required this.total,
    required this.color,
  });

  final String label;
  final int value;
  final int total;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    final radius = context.radius;
    final colorScheme = context.colorScheme;

    final progress = total <= 0 ? 0.0 : (value / total).clamp(0.0, 1.0);

    return Column(
      children: [
        Row(
          children: [
            Expanded(child: Text(label, style: AppTextStyles.small(context))),
            Text(
              '$value',
              style: AppTextStyles.smallNumber(
                context,
              ).copyWith(fontWeight: FontWeight.w700),
            ),
            SizedBox(width: spacing.sm),
            Text(
              '${(progress * 100).toStringAsFixed(1)}%',
              style: AppTextStyles.tiny(
                context,
              ).copyWith(color: colorScheme.onSurfaceVariant),
            ),
          ],
        ),

        SizedBox(height: spacing.sm),

        ClipRRect(
          borderRadius: BorderRadius.circular(radius.sm),
          child: LinearProgressIndicator(
            value: progress,
            minHeight: spacing.xs,
            backgroundColor: colorScheme.surfaceContainerHighest,
            valueColor: AlwaysStoppedAnimation<Color>(color),
          ),
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
    final colorScheme = context.colorScheme;

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
        Text(
          trailing,
          style: AppTextStyles.tiny(
            context,
          ).copyWith(color: colorScheme.onSurfaceVariant),
        ),
      ],
    );
  }
}

class _RoleSummaryCard extends StatelessWidget {
  const _RoleSummaryCard({required this.roles});

  final List<MapEntry<String, KycRoleSummary>> roles;

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    final radius = context.radius;
    final colorScheme = context.colorScheme;

    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(spacing.md),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(radius.borderRadius),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Column(
        children: [
          for (var index = 0; index < roles.length; index++) ...[
            _RoleRow(role: roles[index].key, summary: roles[index].value),
            if (index < roles.length - 1) ...[
              SizedBox(height: spacing.sm),
              Divider(height: spacing.xs, color: colorScheme.outlineVariant),
              SizedBox(height: spacing.sm),
            ],
          ],
        ],
      ),
    );
  }
}

class _RoleRow extends StatelessWidget {
  const _RoleRow({required this.role, required this.summary});

  final String role;
  final KycRoleSummary summary;

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    final iconSize = context.iconSize;
    final colorScheme = context.colorScheme;

    return Row(
      children: [
        Icon(
          _roleIcon(role),
          size: iconSize.medium,
          color: colorScheme.primary,
        ),

        SizedBox(width: spacing.sm),

        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _formatName(role),
                style: AppTextStyles.small(
                  context,
                ).copyWith(fontWeight: FontWeight.w600),
              ),

              SizedBox(height: spacing.xs),

              Text(
                '${summary.totalUsers} users',
                style: AppTextStyles.tiny(
                  context,
                ).copyWith(color: colorScheme.onSurfaceVariant),
              ),
            ],
          ),
        ),

        _RoleMetric(
          label: 'Verified',
          value: summary.verified,
          color: AppColors.success,
        ),

        SizedBox(width: spacing.md),

        _RoleMetric(
          label: 'Pending',
          value: summary.pendingReview,
          color: AppColors.warning,
        ),
      ],
    );
  }
}

class _RoleMetric extends StatelessWidget {
  const _RoleMetric({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final int value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(
          '$value',
          style: AppTextStyles.smallNumber(
            context,
          ).copyWith(color: color, fontWeight: FontWeight.w700),
        ),
        Text(
          label,
          style: AppTextStyles.tiny(
            context,
          ).copyWith(color: colorScheme.onSurfaceVariant),
        ),
      ],
    );
  }
}

class _CountryTabs extends StatelessWidget {
  const _CountryTabs({
    required this.countries,
    required this.selectedCountryCode,
    required this.onChanged,
  });

  final List<KycCountrySummary> countries;
  final String? selectedCountryCode;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;

    return SizedBox(
      height: spacing.xxl,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: countries.length,
        separatorBuilder: (_, _) => SizedBox(width: spacing.sm),
        itemBuilder: (context, index) {
          final country = countries[index];

          final selected =
              country.countryCode.toLowerCase() ==
              selectedCountryCode?.toLowerCase();

          return _CountryTab(
            country: country,
            selected: selected,
            onTap: () {
              onChanged(country.countryCode);
            },
          );
        },
      ),
    );
  }
}

class _CountryTab extends StatelessWidget {
  const _CountryTab({
    required this.country,
    required this.selected,
    required this.onTap,
  });

  final KycCountrySummary country;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    final radius = context.radius;
    final colorScheme = context.colorScheme;

    return Material(
      color: selected ? colorScheme.primary : colorScheme.surface,
      borderRadius: BorderRadius.circular(radius.borderRadius),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(radius.borderRadius),
        child: Container(
          padding: EdgeInsets.symmetric(
            horizontal: spacing.md,
            vertical: spacing.sm,
          ),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(radius.borderRadius),
            border: Border.all(
              color: selected
                  ? colorScheme.primary
                  : colorScheme.outlineVariant,
            ),
          ),
          alignment: Alignment.center,
          child: Text(
            country.countryCode.toUpperCase(),
            style: AppTextStyles.small(context).copyWith(
              color: selected ? colorScheme.onPrimary : colorScheme.onSurface,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}

class _CountrySummaryCard extends StatelessWidget {
  const _CountrySummaryCard({required this.country});

  final KycCountrySummary country;

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    final radius = context.radius;
    final colorScheme = context.colorScheme;

    final roles = country.sortedRoleCounts;

    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(spacing.md),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(radius.borderRadius),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            country.countryName,
            style: AppTextStyles.medium(
              context,
            ).copyWith(fontWeight: FontWeight.w700),
          ),

          SizedBox(height: spacing.xs),

          Text(
            '${country.totalUsers} total users',
            style: AppTextStyles.small(
              context,
            ).copyWith(color: colorScheme.onSurfaceVariant),
          ),

          SizedBox(height: spacing.lg),

          _CountryMetrics(country: country),

          if (roles.isNotEmpty) ...[
            SizedBox(height: spacing.lg),

            Divider(color: colorScheme.outlineVariant),

            SizedBox(height: spacing.md),

            Text(
              'KYC by Role',
              style: AppTextStyles.small(
                context,
              ).copyWith(fontWeight: FontWeight.w700),
            ),

            SizedBox(height: spacing.md),

            for (var index = 0; index < roles.length; index++) ...[
              _RoleRow(role: roles[index].key, summary: roles[index].value),
              if (index < roles.length - 1) SizedBox(height: spacing.md),
            ],
          ],
        ],
      ),
    );
  }
}

class _CountryMetrics extends StatelessWidget {
  const _CountryMetrics({required this.country});

  final KycCountrySummary country;

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;

    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _CountryMetric(
                label: 'Verified',
                value: country.verified,
                color: AppColors.success,
              ),
            ),
            SizedBox(width: spacing.sm),
            Expanded(
              child: _CountryMetric(
                label: 'Pending',
                value: country.pendingReview,
                color: AppColors.warning,
              ),
            ),
          ],
        ),

        SizedBox(height: spacing.sm),

        Row(
          children: [
            Expanded(
              child: _CountryMetric(
                label: 'Started',
                value: country.started,
                color: AppColors.info,
              ),
            ),
            SizedBox(width: spacing.sm),
            Expanded(
              child: _CountryMetric(
                label: 'Not Started',
                value: country.notStarted,
                color: context.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _CountryMetric extends StatelessWidget {
  const _CountryMetric({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final int value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    final radius = context.radius;
    final colorScheme = context.colorScheme;

    return Container(
      padding: EdgeInsets.all(spacing.md),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(radius.borderRadius),
        border: Border.all(color: color.withValues(alpha: 0.20)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$value',
            style: AppTextStyles.mediumNumber(
              context,
            ).copyWith(fontWeight: FontWeight.w700),
          ),

          SizedBox(height: spacing.xs),

          Text(
            label,
            style: AppTextStyles.tiny(
              context,
            ).copyWith(color: colorScheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

IconData _roleIcon(String role) {
  switch (role.trim().toLowerCase()) {
    case 'customer':
    case 'user':
      return Icons.person_outline;

    case 'agent':
      return Icons.support_agent_outlined;

    case 'merchant':
    case 'vendor':
      return Icons.storefront_outlined;

    case 'finance':
    case 'accounts':
      return Icons.account_balance_outlined;

    case 'treasury':
      return Icons.savings_outlined;

    case 'compliance':
    case 'audit':
      return Icons.verified_user_outlined;

    case 'admin':
      return Icons.admin_panel_settings_outlined;

    default:
      return Icons.badge_outlined;
  }
}

String _formatName(String value) {
  final normalized = value.trim().replaceAll('_', ' ');

  if (normalized.isEmpty) {
    return 'Unknown';
  }

  return normalized
      .split(' ')
      .where((part) => part.isNotEmpty)
      .map(
        (part) =>
            '${part[0].toUpperCase()}'
            '${part.substring(1).toLowerCase()}',
      )
      .join(' ');
}
