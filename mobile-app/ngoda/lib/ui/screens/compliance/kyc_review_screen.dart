import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:ngoda/data_models/user/user_details.dart';
import 'package:ngoda/ui/extensions/app_size.dart';
import 'package:ngoda/ui/extensions/theme_extension.dart';
import 'package:ngoda/ui/screens/compliance/providers/user_kyc_review_provider.dart';
import 'package:ngoda/ui/shared/app_colors.dart';
import 'package:ngoda/ui/shared/app_text_styles.dart';
import 'package:ngoda/ui/widgets/app_error_state.dart';
import 'package:ngoda/ui/widgets/app_loader.dart';
import 'package:ngoda/ui/widgets/view_header.dart';

class KycReviewScreen extends ConsumerWidget {
  const KycReviewScreen({super.key, required this.userId});

  final String userId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncData = ref.watch(userKycReviewProvider(userId));

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            ViewHeader(title: 'KYC Review', onClose: context.pop),
            Expanded(
              child: asyncData.when(
                loading: () => const AppLoader(
                  message: 'Loading KYC review',
                  fullScreen: true,
                ),
                error: (error, _) {
                  return AppErrorState(message: error.toString());
                },
                data: (response) {
                  if (response.error != null) {
                    return AppErrorState(message: response.error.toString());
                  }

                  final review = response.result;

                  if (review == null) {
                    return const _ReviewNotFound();
                  }

                  return _KycReviewContent(review: review);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _KycReviewContent extends StatelessWidget {
  const _KycReviewContent({required this.review});

  final UserDetails review;

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: EdgeInsets.fromLTRB(
        spacing.md,
        spacing.md,
        spacing.md,
        spacing.lg,
      ),
      children: [
        _CustomerHeader(review: review),

        SizedBox(height: spacing.md),

        _StatusCard(review: review),

        SizedBox(height: spacing.lg),

        Text(
          'Review Information',
          style: AppTextStyles.small(
            context,
          ).copyWith(fontWeight: FontWeight.w700),
        ),

        SizedBox(height: spacing.sm),

        _ReviewActionCard(
          icon: Icons.person_outline,
          title: 'Personal Information',
          subtitle: 'Review personal and contact information',
          onTap: () {
            context.push(
              '/user-kyc-review/'
              '${review.userId}/details',
              extra: review,
            );
          },
        ),

        SizedBox(height: spacing.sm),

        _ReviewActionCard(
          icon: Icons.badge_outlined,
          title: 'KYC Details',
          subtitle: 'Review identification and financial information',
          onTap: () {
            context.push(
              '/user-kyc-review/'
              '${review.userId}/kyc-details',
              extra: review.kycDetails,
            );
          },
        ),

        SizedBox(height: spacing.sm),

        _ReviewActionCard(
          icon: Icons.folder_copy_outlined,
          title: 'Verification Documents',
          subtitle: 'Review submitted verification documents',
          onTap: () {
            context.push(
              '/compliance/kyc/'
              '${review.userId}/documents',
              extra: review.verificationDocuments,
            );
          },
        ),

        SizedBox(height: spacing.sm),

        _ReviewActionCard(
          icon: Icons.fact_check_outlined,
          title: 'Review Decision',
          subtitle: 'Approve, request changes or reject this KYC review',
          onTap: () {
            context.push(
              '/compliance/kyc/'
              '${review.userId}/decision',
              extra: review,
            );
          },
        ),
      ],
    );
  }
}

class _CustomerHeader extends StatelessWidget {
  const _CustomerHeader({required this.review});

  final UserDetails review;

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    final iconSize = context.iconSize;
    final colorScheme = context.colorScheme;

    final name = review.fullName.trim();
    final contact = _contactValue(review);
    final countryCode = review.contactDetails.countryCode?.trim() ?? '';

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          width: spacing.xxxxl,
          height: spacing.xxxxl,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: colorScheme.primary.withValues(alpha: 0.10),
            shape: BoxShape.circle,
          ),
          child: name.isEmpty
              ? Icon(
                  Icons.person_outline,
                  size: iconSize.xl,
                  color: colorScheme.primary,
                )
              : Text(
                  name[0].toUpperCase(),
                  style: AppTextStyles.large(context).copyWith(
                    color: colorScheme.primary,
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
                name.isEmpty ? 'Unknown User' : name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyles.medium(
                  context,
                ).copyWith(fontWeight: FontWeight.w700),
              ),

              if (contact.isNotEmpty) ...[
                SizedBox(height: spacing.xs),

                Text(
                  contact,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.tiny(
                    context,
                  ).copyWith(color: colorScheme.onSurfaceVariant),
                ),
              ],

              if (countryCode.isNotEmpty) ...[
                SizedBox(height: spacing.sm),

                _InfoBadge(
                  icon: Icons.public,
                  label: countryCode.toUpperCase(),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.review});

  final UserDetails review;

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    final radius = context.radius;
    final iconSize = context.iconSize;
    final colorScheme = context.colorScheme;

    final status = review.kycDetails.status?.trim() ?? '';

    final statusLabel = status.isEmpty ? 'Not Started' : _formatValue(status);

    final statusColor = _statusColor(context, status);

    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(spacing.md),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(radius.cardRadius),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Row(
        children: [
          Container(
            width: spacing.xxl,
            height: spacing.xxl,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: 0.10),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.verified_user_outlined,
              size: iconSize.medium,
              color: statusColor,
            ),
          ),

          SizedBox(width: spacing.md),

          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'KYC Status',
                  style: AppTextStyles.tiny(
                    context,
                  ).copyWith(color: colorScheme.onSurfaceVariant),
                ),

                SizedBox(height: spacing.xs),

                Text(
                  statusLabel,
                  style: AppTextStyles.small(
                    context,
                  ).copyWith(color: statusColor, fontWeight: FontWeight.w700),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ReviewActionCard extends StatelessWidget {
  const _ReviewActionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    final radius = context.radius;
    final iconSize = context.iconSize;
    final colorScheme = context.colorScheme;

    return Material(
      color: colorScheme.surface,
      borderRadius: BorderRadius.circular(radius.cardRadius),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(radius.cardRadius),
        child: Container(
          width: double.infinity,
          padding: EdgeInsets.all(spacing.md),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(radius.cardRadius),
            border: Border.all(color: colorScheme.outlineVariant),
          ),
          child: Row(
            children: [
              Container(
                width: spacing.xxl,
                height: spacing.xxl,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: colorScheme.primary.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(radius.md),
                ),
                child: Icon(
                  icon,
                  size: iconSize.medium,
                  color: colorScheme.primary,
                ),
              ),

              SizedBox(width: spacing.md),

              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: AppTextStyles.small(
                        context,
                      ).copyWith(fontWeight: FontWeight.w600),
                    ),

                    SizedBox(height: spacing.xs),

                    Text(
                      subtitle,
                      style: AppTextStyles.tiny(
                        context,
                      ).copyWith(color: colorScheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),

              SizedBox(width: spacing.sm),

              Icon(
                Icons.chevron_right,
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

class _InfoBadge extends StatelessWidget {
  const _InfoBadge({required this.icon, required this.label});

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

class _ReviewNotFound extends StatelessWidget {
  const _ReviewNotFound();

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
              Icons.person_search_outlined,
              size: iconSize.xl,
              color: colorScheme.onSurfaceVariant,
            ),

            SizedBox(height: spacing.md),

            Text(
              'KYC review not found',
              style: AppTextStyles.medium(
                context,
              ).copyWith(fontWeight: FontWeight.w600),
            ),

            SizedBox(height: spacing.xs),

            Text(
              'The requested KYC review '
              'is not available.',
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

String _contactValue(UserDetails review) {
  final email = review.contactDetails.email?.trim() ?? '';

  final phone = review.contactDetails.phone?.trim() ?? '';

  if (email.isNotEmpty && phone.isNotEmpty) {
    return '$email • $phone';
  }

  if (email.isNotEmpty) {
    return email;
  }

  if (phone.isNotEmpty) {
    return phone;
  }

  return '';
}

Color _statusColor(BuildContext context, String status) {
  switch (status.trim().toLowerCase()) {
    case 'verified':
    case 'approved':
      return AppColors.success;

    case 'pending':
    case 'pendingreview':
    case 'pending_review':
    case 'underreview':
    case 'under_review':
      return AppColors.warning;

    case 'rejected':
      return AppColors.error;

    default:
      return context.colorScheme.primary;
  }
}

String _formatValue(String value) {
  var formatted = value.trim();

  if (formatted.contains('.')) {
    formatted = formatted.split('.').last;
  }

  formatted = formatted.replaceAllMapped(
    RegExp(r'([a-z])([A-Z])'),
    (match) => '${match.group(1)} ${match.group(2)}',
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
