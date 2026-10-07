import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:ngoda/data_models/admin/operational_country.dart';
import 'package:ngoda/ui/extensions/app_size.dart';
import 'package:ngoda/ui/screens/admin/provider/admin_dashboard_provider.dart';
import 'package:ngoda/ui/shared/app_text_styles.dart';
import 'package:ngoda/ui/widgets/app_empty_state.dart';
import 'package:ngoda/ui/widgets/app_error_state.dart';
import 'package:ngoda/ui/widgets/app_loader.dart';
import 'package:ngoda/ui/widgets/view_header.dart';

class CountryListScreen extends ConsumerWidget {
  const CountryListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dashboardAsync = ref.watch(adminDashboardProvider);

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            ViewHeader(
              title: 'Operational Countries',
              onClose: () {
                context.pop();
              },
            ),

            Expanded(
              child: dashboardAsync.when(
                loading: () => const AppLoader(),
                error: (error, stackTrace) {
                  return AppErrorState(
                    message: error.toString(),
                    buttonText: 'Retry',
                    onAction: () {
                      ref.invalidate(adminDashboardProvider);
                    },
                  );
                },
                data: (response) {
                  if (response.error != null) {
                    return AppErrorState(
                      message: response.error!,
                      buttonText: 'Retry',
                      onAction: () {
                        ref.invalidate(adminDashboardProvider);
                      },
                    );
                  }

                  final dashboard = response.result;

                  if (dashboard == null) {
                    return AppErrorState(
                      message: 'Failed to load operational countries',
                      buttonText: 'Retry',
                      onAction: () {
                        ref.invalidate(adminDashboardProvider);
                      },
                    );
                  }

                  final countries = dashboard.operationalCountries;

                  if (countries.isEmpty) {
                    return const AppEmptyState(
                      message: 'No operational countries found',
                    );
                  }

                  return _CountryList(countries: countries);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CountryList extends StatelessWidget {
  final List<OperationalCountry> countries;

  const _CountryList({required this.countries});

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;

    return ListView.separated(
      padding: EdgeInsets.fromLTRB(
        spacing.md,
        spacing.md,
        spacing.md,
        spacing.lg,
      ),
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      itemCount: countries.length,
      separatorBuilder: (context, index) {
        return SizedBox(height: spacing.sm);
      },
      itemBuilder: (context, index) {
        return _CountryDetails(country: countries[index]);
      },
    );
  }
}

class _CountryDetails extends StatefulWidget {
  final OperationalCountry country;

  const _CountryDetails({required this.country});

  @override
  State<_CountryDetails> createState() => _CountryDetailsState();
}

class _CountryDetailsState extends State<_CountryDetails> {
  bool expanded = false;

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    final radius = context.radius;
    final iconSize = context.iconSize;
    final colorScheme = Theme.of(context).colorScheme;

    final country = widget.country;

    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(radius.cardRadius),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Column(
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(radius.cardRadius),
            onTap: () {
              context.push('/country/add-operational-country', extra: country);
            },
            child: Padding(
              padding: EdgeInsets.all(spacing.md),
              child: Row(
                children: [
                  Container(
                    padding: EdgeInsets.symmetric(
                      horizontal: spacing.md,
                      vertical: spacing.sm,
                    ),
                    decoration: BoxDecoration(
                      color: colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(radius.md),
                    ),
                    child: Text(
                      country.countryCode.toUpperCase(),
                      style: AppTextStyles.small(context).copyWith(
                        color: colorScheme.onPrimaryContainer,
                        fontWeight: FontWeight.w700,
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
                          ).copyWith(fontWeight: FontWeight.w600),
                        ),

                        SizedBox(height: spacing.xs),

                        Text(
                          '${country.currencies.length} '
                          '${country.currencies.length == 1 ? 'currency' : 'currencies'}',
                          style: AppTextStyles.tiny(
                            context,
                          ).copyWith(color: colorScheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),

                  _StatusBadge(isActive: country.isActive),

                  SizedBox(width: spacing.sm),

                  InkWell(
                    borderRadius: BorderRadius.circular(radius.xl),
                    onTap: () {
                      setState(() {
                        expanded = !expanded;
                      });
                    },
                    child: Padding(
                      padding: EdgeInsets.all(spacing.sm),
                      child: Icon(
                        expanded
                            ? Icons.keyboard_arrow_up_rounded
                            : Icons.keyboard_arrow_down_rounded,
                        size: iconSize.large,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          AnimatedCrossFade(
            duration: const Duration(milliseconds: 200),
            crossFadeState: expanded
                ? CrossFadeState.showSecond
                : CrossFadeState.showFirst,
            firstChild: const SizedBox.shrink(),
            secondChild: _CountryCurrencies(country: country),
          ),
        ],
      ),
    );
  }
}

class _CountryCurrencies extends StatelessWidget {
  final OperationalCountry country;

  const _CountryCurrencies({required this.country});

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    final radius = context.radius;
    final colorScheme = Theme.of(context).colorScheme;

    if (country.currencies.isEmpty) {
      return Padding(
        padding: EdgeInsets.fromLTRB(spacing.md, 0, spacing.md, spacing.md),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Text(
            'No currencies configured',
            style: AppTextStyles.tiny(
              context,
            ).copyWith(color: colorScheme.onSurfaceVariant),
          ),
        ),
      );
    }

    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(spacing.md, 0, spacing.md, spacing.md),
      child: Wrap(
        spacing: spacing.sm,
        runSpacing: spacing.sm,
        children: country.currencies.map((currency) {
          return Container(
            padding: EdgeInsets.symmetric(
              horizontal: spacing.md,
              vertical: spacing.sm,
            ),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(radius.borderRadius),
            ),
            child: Text(
              currency.code.toUpperCase(),
              style: AppTextStyles.tiny(
                context,
              ).copyWith(fontWeight: FontWeight.w600),
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final bool isActive;

  const _StatusBadge({required this.isActive});

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    final radius = context.radius;
    final colorScheme = Theme.of(context).colorScheme;

    final statusColor = isActive ? Colors.green : colorScheme.error;

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: spacing.sm,
        vertical: spacing.xs,
      ),
      decoration: BoxDecoration(
        color: statusColor.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(radius.borderRadius),
      ),
      child: Text(
        isActive ? 'Active' : 'Not Active',
        style: AppTextStyles.tiny(
          context,
        ).copyWith(color: statusColor, fontWeight: FontWeight.w600),
      ),
    );
  }
}
