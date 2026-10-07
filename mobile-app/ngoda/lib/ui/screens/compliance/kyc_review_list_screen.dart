import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:ngoda/data_models/common/report_pagination.dart';
import 'package:ngoda/data_models/kyc/user_kyc_review_page.dart';
import 'package:ngoda/data_models/kyc/user_kyc_review_summary.dart';
import 'package:ngoda/data_models/params/kyc_review_params.dart';
import 'package:ngoda/ui/enums/enums.dart';

import 'package:ngoda/ui/extensions/app_size.dart';
import 'package:ngoda/ui/extensions/theme_extension.dart';
import 'package:ngoda/ui/screens/compliance/providers/compliance_kyc_reviews_provider.dart';
import 'package:ngoda/ui/shared/app_text_styles.dart';
import 'package:ngoda/ui/widgets/app_error_state.dart';
import 'package:ngoda/ui/widgets/app_loader.dart';
import 'package:ngoda/ui/widgets/view_header.dart';

class KycReviewListScreen extends ConsumerWidget {
  const KycReviewListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final initialParams = KycReviewQueueParams(page: 1, pageSize: 50);
    final asyncData = ref.watch(complianceKycReviewsProvider(initialParams));

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            ViewHeader(title: 'KYC Reviews', onClose: context.pop),
            Expanded(
              child: asyncData.when(
                loading: () => const AppLoader(
                  message: 'Loading KYC reviews',
                  fullScreen: true,
                ),
                error: (error, _) {
                  return AppErrorState(message: error.toString());
                },
                data: (response) {
                  if (response.error != null) {
                    return AppErrorState(message: response.error.toString());
                  }

                  final page = response.result;

                  if (page == null || page.data.isEmpty) {
                    return const _EmptyKycReviews();
                  }

                  return _KycReviewList(page: page);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _KycReviewList extends StatelessWidget {
  const _KycReviewList({required this.page});

  final UserKycReviewPage page;

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;

    final groups = page.groupedByCountry;

    return Column(
      children: [
        _ListSummary(page: page, countryCount: groups.length),
        Expanded(
          child: ListView.builder(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: EdgeInsets.fromLTRB(
              spacing.md,
              spacing.md,
              spacing.md,
              spacing.lg,
            ),
            itemCount: groups.length,
            itemBuilder: (context, index) {
              final entry = groups.entries.elementAt(index);

              return Padding(
                padding: EdgeInsets.only(bottom: spacing.lg),
                child: _CountryGroup(
                  countryCode: entry.key,
                  initialUsers: entry.value,
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _ListSummary extends StatelessWidget {
  const _ListSummary({required this.page, required this.countryCount});

  final UserKycReviewPage page;
  final int countryCount;

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    final colorScheme = context.colorScheme;

    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(
        horizontal: spacing.md,
        vertical: spacing.sm,
      ),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        border: Border(bottom: BorderSide(color: colorScheme.outlineVariant)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              '${page.pagination.totalEntries} users',
              style: AppTextStyles.small(
                context,
              ).copyWith(fontWeight: FontWeight.w600),
            ),
          ),
          Text(
            '$countryCount '
            '${countryCount == 1 ? 'country' : 'countries'}',
            style: AppTextStyles.tiny(
              context,
            ).copyWith(color: colorScheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

class _CountryGroup extends ConsumerStatefulWidget {
  const _CountryGroup({required this.countryCode, required this.initialUsers});

  final String countryCode;
  final List<UserKycReviewSummary> initialUsers;

  @override
  ConsumerState<_CountryGroup> createState() => _CountryGroupState();
}

class _CountryGroupState extends ConsumerState<_CountryGroup> {
  static const int _pageSize = 20;

  int _page = 1;

  KycReviewQueueParams get _params => KycReviewQueueParams(
    page: _page,
    pageSize: _pageSize,
    countryCode: widget.countryCode,
  );

  @override
  Widget build(BuildContext context) {
    final asyncData = ref.watch(complianceKycReviewsProvider(_params));

    return asyncData.when(
      loading: () {
        /*
         * The first global request already contains
         * users grouped by country. Keep displaying
         * those users while the country-specific
         * first page is being fetched.
         */
        if (_page == 1 && widget.initialUsers.isNotEmpty) {
          return _CountryContent(
            countryCode: widget.countryCode,
            users: widget.initialUsers,
            isLoading: true,
          );
        }

        return _CountryLoading(countryCode: widget.countryCode);
      },
      error: (error, _) {
        /*
         * The initial global data is still useful
         * if the first country-specific request
         * fails.
         */
        if (_page == 1 && widget.initialUsers.isNotEmpty) {
          return _CountryContent(
            countryCode: widget.countryCode,
            users: widget.initialUsers,
          );
        }

        return _CountryError(
          countryCode: widget.countryCode,
          message: error.toString(),
        );
      },
      data: (response) {
        if (response.error != null) {
          if (_page == 1 && widget.initialUsers.isNotEmpty) {
            return _CountryContent(
              countryCode: widget.countryCode,
              users: widget.initialUsers,
            );
          }

          return _CountryError(
            countryCode: widget.countryCode,
            message: response.error.toString(),
          );
        }

        final page = response.result;

        if (page == null) {
          return _CountryContent(
            countryCode: widget.countryCode,
            users: _page == 1 ? widget.initialUsers : const [],
          );
        }

        return _CountryContent(
          countryCode: widget.countryCode,
          users: page.data,
          pagination: page.pagination,
          onPrevious: page.pagination.page > 1 ? _previousPage : null,
          onNext: page.pagination.page < page.pagination.totalPages
              ? _nextPage
              : null,
        );
      },
    );
  }

  void _previousPage() {
    if (_page <= 1) {
      return;
    }

    setState(() {
      _page--;
    });
  }

  void _nextPage() {
    setState(() {
      _page++;
    });
  }
}

class _CountryContent extends StatelessWidget {
  const _CountryContent({
    required this.countryCode,
    required this.users,
    this.pagination,
    this.onPrevious,
    this.onNext,
    this.isLoading = false,
  });

  final String countryCode;
  final List<UserKycReviewSummary> users;
  final ReportPagination? pagination;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    final iconSize = context.iconSize;
    final colorScheme = context.colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              Icons.public,
              size: iconSize.medium,
              color: colorScheme.primary,
            ),

            SizedBox(width: spacing.sm),

            Expanded(
              child: Text(
                countryCode.toUpperCase(),
                style: AppTextStyles.medium(
                  context,
                ).copyWith(fontWeight: FontWeight.w600),
              ),
            ),

            if (isLoading) ...[
              SizedBox(
                width: iconSize.medium,
                height: iconSize.medium,
                child: const CircularProgressIndicator(strokeWidth: 2),
              ),

              SizedBox(width: spacing.sm),
            ],

            Text(
              pagination == null
                  ? '${users.length}'
                  : '${pagination!.totalEntries}',
              style: AppTextStyles.tiny(
                context,
              ).copyWith(color: colorScheme.onSurfaceVariant),
            ),
          ],
        ),

        SizedBox(height: spacing.sm),

        if (users.isEmpty)
          _EmptyCountry()
        else
          ...users.map(
            (user) => Padding(
              padding: EdgeInsets.only(bottom: spacing.sm),
              child: _KycUserCard(user: user),
            ),
          ),

        if (pagination != null && pagination!.totalPages > 1) ...[
          SizedBox(height: spacing.xs),

          _PaginationBar(
            pagination: pagination!,
            onPrevious: onPrevious,
            onNext: onNext,
          ),
        ],
      ],
    );
  }
}

class _KycUserCard extends StatelessWidget {
  const _KycUserCard({required this.user});

  final UserKycReviewSummary user;

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    final radius = context.radius;
    final iconSize = context.iconSize;
    final colorScheme = context.colorScheme;

    final enabled = user.hasKyc;

    return Material(
      color: colorScheme.surface,
      borderRadius: BorderRadius.circular(radius.cardRadius),
      child: InkWell(
        onTap: !enabled
            ? null
            : () {
                context.push(
                  '/pending-kyc-review/'
                  'user-kyc-review/'
                  '${user.userId}',
                );
              },
        borderRadius: BorderRadius.circular(radius.cardRadius),
        child: Container(
          width: double.infinity,
          padding: EdgeInsets.all(spacing.md),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(radius.cardRadius),
            border: Border.all(color: colorScheme.outlineVariant),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              _UserAvatar(user: user),

              SizedBox(width: spacing.md),

              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      user.fullName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.small(context).copyWith(
                        fontWeight: FontWeight.w600,
                        color: enabled
                            ? colorScheme.onSurface
                            : colorScheme.onSurfaceVariant,
                      ),
                    ),

                    SizedBox(height: spacing.xs),

                    _ContactText(email: user.email, phone: user.phone),

                    SizedBox(height: spacing.sm),

                    Wrap(
                      spacing: spacing.sm,
                      runSpacing: spacing.xs,
                      children: [
                        _RoleBadge(role: user.role),
                        _KycStatusBadge(status: user.kycStatus),
                      ],
                    ),

                    if (user.kycUpdatedAt != null ||
                        user.kycStartedAt != null) ...[
                      SizedBox(height: spacing.sm),

                      _UpdatedText(
                        date: user.kycUpdatedAt ?? user.kycStartedAt!,
                      ),
                    ],
                  ],
                ),
              ),

              SizedBox(width: spacing.sm),

              Icon(
                enabled ? Icons.chevron_right : Icons.block_outlined,
                size: iconSize.medium,
                color: colorScheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _UserAvatar extends StatelessWidget {
  const _UserAvatar({required this.user});

  final UserKycReviewSummary user;

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    final iconSize = context.iconSize;
    final colorScheme = context.colorScheme;

    final initial = _initialFor(user.fullName);

    return Container(
      width: spacing.xxxl,
      height: spacing.xxxl,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: colorScheme.primary.withValues(alpha: 0.10),
        shape: BoxShape.circle,
      ),
      child: initial == null
          ? Icon(
              Icons.person_outline,
              size: iconSize.large,
              color: colorScheme.primary,
            )
          : Text(
              initial,
              style: AppTextStyles.medium(context).copyWith(
                color: colorScheme.primary,
                fontWeight: FontWeight.w700,
              ),
            ),
    );
  }
}

class _ContactText extends StatelessWidget {
  const _ContactText({required this.email, required this.phone});

  final String? email;
  final String? phone;

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;

    final value = _contactValue(email, phone);

    return Text(
      value,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: AppTextStyles.tiny(
        context,
      ).copyWith(color: colorScheme.onSurfaceVariant),
    );
  }
}

class _RoleBadge extends StatelessWidget {
  const _RoleBadge({required this.role});

  final String role;

  @override
  Widget build(BuildContext context) {
    return _Badge(icon: Icons.badge_outlined, label: _formatValue(role));
  }
}

class _KycStatusBadge extends StatelessWidget {
  const _KycStatusBadge({required this.status});

  final KycReviewStatus status;

  @override
  Widget build(BuildContext context) {
    return _Badge(
      icon: Icons.verified_user_outlined,
      label: _formatValue(status.name),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    final radius = context.radius;
    final iconSize = context.iconSize;
    final colorScheme = context.colorScheme;

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: spacing.sm,
        vertical: spacing.xs,
      ),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(radius.sm),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: iconSize.small, color: colorScheme.onSurfaceVariant),

          SizedBox(width: spacing.xs),

          Text(
            label,
            style: AppTextStyles.tiny(context).copyWith(
              color: colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _UpdatedText extends StatelessWidget {
  const _UpdatedText({required this.date});

  final DateTime date;

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    final iconSize = context.iconSize;
    final colorScheme = context.colorScheme;

    return Row(
      children: [
        Icon(
          Icons.schedule_outlined,
          size: iconSize.small,
          color: colorScheme.onSurfaceVariant,
        ),

        SizedBox(width: spacing.xs),

        Expanded(
          child: Text(
            'Updated ${_formatDate(date)}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTextStyles.tiny(
              context,
            ).copyWith(color: colorScheme.onSurfaceVariant),
          ),
        ),
      ],
    );
  }
}

class _PaginationBar extends StatelessWidget {
  const _PaginationBar({
    required this.pagination,
    required this.onPrevious,
    required this.onNext,
  });

  final ReportPagination pagination;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    final radius = context.radius;
    final iconSize = context.iconSize;
    final colorScheme = context.colorScheme;

    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(
        horizontal: spacing.sm,
        vertical: spacing.xs,
      ),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(radius.borderRadius),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: onPrevious,
            icon: Icon(Icons.chevron_left, size: iconSize.medium),
          ),

          Expanded(
            child: Text(
              'Page ${pagination.page} '
              'of ${pagination.totalPages}',
              textAlign: TextAlign.center,
              style: AppTextStyles.tiny(context).copyWith(
                color: colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),

          IconButton(
            onPressed: onNext,
            icon: Icon(Icons.chevron_right, size: iconSize.medium),
          ),
        ],
      ),
    );
  }
}

class _CountryLoading extends StatelessWidget {
  const _CountryLoading({required this.countryCode});

  final String countryCode;

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    final iconSize = context.iconSize;
    final colorScheme = context.colorScheme;

    return Row(
      children: [
        Icon(Icons.public, size: iconSize.medium, color: colorScheme.primary),

        SizedBox(width: spacing.sm),

        Expanded(
          child: Text(
            countryCode.toUpperCase(),
            style: AppTextStyles.medium(
              context,
            ).copyWith(fontWeight: FontWeight.w600),
          ),
        ),

        SizedBox(
          width: iconSize.medium,
          height: iconSize.medium,
          child: const CircularProgressIndicator(strokeWidth: 2),
        ),
      ],
    );
  }
}

class _CountryError extends StatelessWidget {
  const _CountryError({required this.countryCode, required this.message});

  final String countryCode;
  final String message;

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    final radius = context.radius;
    final iconSize = context.iconSize;
    final colorScheme = context.colorScheme;

    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(spacing.md),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(radius.cardRadius),
        border: Border.all(color: colorScheme.error),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.error_outline,
            size: iconSize.medium,
            color: colorScheme.error,
          ),

          SizedBox(width: spacing.sm),

          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  countryCode.toUpperCase(),
                  style: AppTextStyles.small(
                    context,
                  ).copyWith(fontWeight: FontWeight.w600),
                ),

                SizedBox(height: spacing.xs),

                Text(
                  message,
                  style: AppTextStyles.tiny(
                    context,
                  ).copyWith(color: colorScheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyCountry extends StatelessWidget {
  const _EmptyCountry();

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
        borderRadius: BorderRadius.circular(radius.cardRadius),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Text(
        'No KYC reviews for this country.',
        textAlign: TextAlign.center,
        style: AppTextStyles.tiny(
          context,
        ).copyWith(color: colorScheme.onSurfaceVariant),
      ),
    );
  }
}

class _EmptyKycReviews extends StatelessWidget {
  const _EmptyKycReviews();

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    final iconSize = context.iconSize;
    final colorScheme = context.colorScheme;

    return Center(
      child: Padding(
        padding: EdgeInsets.all(spacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.fact_check_outlined,
              size: iconSize.xl,
              color: colorScheme.onSurfaceVariant,
            ),

            SizedBox(height: spacing.md),

            Text(
              'No KYC reviews',
              style: AppTextStyles.medium(
                context,
              ).copyWith(fontWeight: FontWeight.w600),
            ),

            SizedBox(height: spacing.xs),

            Text(
              'There are no KYC reviews '
              'available at the moment.',
              textAlign: TextAlign.center,
              style: AppTextStyles.tiny(
                context,
              ).copyWith(color: colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}

String? _initialFor(String value) {
  final trimmed = value.trim();

  if (trimmed.isEmpty || trimmed == 'Unknown User') {
    return null;
  }

  return trimmed[0].toUpperCase();
}

String _contactValue(String? email, String? phone) {
  final normalizedEmail = email?.trim() ?? '';

  final normalizedPhone = phone?.trim() ?? '';

  if (normalizedEmail.isNotEmpty && normalizedPhone.isNotEmpty) {
    return '$normalizedEmail • '
        '$normalizedPhone';
  }

  if (normalizedEmail.isNotEmpty) {
    return normalizedEmail;
  }

  if (normalizedPhone.isNotEmpty) {
    return normalizedPhone;
  }

  return 'No contact information';
}

String _formatDate(DateTime value) {
  final day = value.day.toString().padLeft(2, '0');

  final month = value.month.toString().padLeft(2, '0');

  return '$day/$month/${value.year}';
}

String _formatValue(String value) {
  var formatted = value.trim();

  if (formatted.contains('.')) {
    formatted = formatted.split('.').last;
  }

  formatted = formatted.replaceAllMapped(
    RegExp(r'([a-z])([A-Z])'),
    (match) =>
        '${match.group(1)} '
        '${match.group(2)}',
  );

  formatted = formatted.replaceAll('_', ' ');

  if (formatted.isEmpty) {
    return 'Unknown';
  }

  return formatted
      .split(' ')
      .where((part) => part.isNotEmpty)
      .map(
        (part) =>
            '${part[0].toUpperCase()}'
            '${part.substring(1).toLowerCase()}',
      )
      .join(' ');
}
