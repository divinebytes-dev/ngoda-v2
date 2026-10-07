import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:ngoda/data_models/gamification/badges/loyalty_badge.dart';
import 'package:ngoda/data_models/gamification/badges/loyalty_badge_collection.dart';
import 'package:ngoda/data_models/gamification/badges/loyalty_badge_summary.dart';
import 'package:ngoda/ui/extensions/app_size.dart';
import 'package:ngoda/ui/extensions/theme_extension.dart';
import 'package:ngoda/ui/screens/gamification/provider/loyalty_badges_provider.dart';
import 'package:ngoda/ui/shared/app_text_styles.dart';
import 'package:ngoda/ui/widgets/app_empty_state.dart';
import 'package:ngoda/ui/widgets/app_error_state.dart';
import 'package:ngoda/ui/widgets/app_loader.dart';
import 'package:ngoda/ui/widgets/view_header.dart';

class LoyaltyBadgesScreen extends ConsumerWidget {
  const LoyaltyBadgesScreen({super.key});

  Future<void> _refresh(WidgetRef ref) async {
    ref.invalidate(loyaltyBadgesProvider);

    await ref.read(loyaltyBadgesProvider.future);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final badgesAsync = ref.watch(loyaltyBadgesProvider);

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            ViewHeader(
              title: 'Badges',
              onClose: () {
                context.pop();
              },
            ),
            Expanded(
              child: RefreshIndicator(
                onRefresh: () {
                  return _refresh(ref);
                },
                child: badgesAsync.when(
                  loading: () => const AppLoader(
                    message: 'Loading badges',
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

                    final collection = response.result;

                    if (collection == null || collection.rows.isEmpty) {
                      return const _RefreshableState(child: AppEmptyState());
                    }

                    return _BadgesContent(collection: collection);
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

class _BadgesContent extends StatelessWidget {
  final LoyaltyBadgeCollection collection;

  const _BadgesContent({required this.collection});

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: EdgeInsets.fromLTRB(spacing.md, 0, spacing.md, spacing.xxl),
      children: [
        _BadgeSummaryCard(summary: collection.summary),
        SizedBox(height: spacing.lg),
        Text(
          'Your collection',
          style: AppTextStyles.small(
            context,
          ).copyWith(fontWeight: FontWeight.w800),
        ),
        SizedBox(height: spacing.sm),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: collection.rows.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            crossAxisSpacing: spacing.sm,
            mainAxisSpacing: spacing.sm,
            childAspectRatio: 0.78,
          ),
          itemBuilder: (context, index) {
            return _BadgeCard(badge: collection.rows[index]);
          },
        ),
      ],
    );
  }
}

class _BadgeSummaryCard extends StatelessWidget {
  final LoyaltyBadgeSummary summary;

  const _BadgeSummaryCard({required this.summary});

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    final radius = context.radius;
    final iconSize = context.iconSize;

    final progress = summary.total == 0
        ? 0.0
        : (summary.earned / summary.total).clamp(0.0, 1.0).toDouble();

    return Container(
      padding: EdgeInsets.all(spacing.lg),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [_BadgeColors.gold, _BadgeColors.darkGold],
        ),
        borderRadius: BorderRadius.circular(radius.cardRadius),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: iconSize.xl * 1.5,
                height: iconSize.xl * 1.5,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.18),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.military_tech_rounded,
                  size: iconSize.medium,
                  color: Colors.white,
                ),
              ),
              SizedBox(width: spacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${summary.earned} of ${summary.total} earned',
                      style: AppTextStyles.medium(context).copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    SizedBox(height: spacing.xs),
                    Text(
                      summary.remaining == 0
                          ? 'Collection complete'
                          : '${summary.remaining} badges still to unlock',
                      style: AppTextStyles.tiny(
                        context,
                      ).copyWith(color: Colors.white.withValues(alpha: 0.82)),
                    ),
                  ],
                ),
              ),
            ],
          ),
          SizedBox(height: spacing.lg),
          ClipRRect(
            borderRadius: BorderRadius.circular(radius.borderRadius),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: spacing.sm,
              color: Colors.white,
              backgroundColor: Colors.white.withValues(alpha: 0.22),
            ),
          ),
        ],
      ),
    );
  }
}

class _BadgeCard extends StatelessWidget {
  final LoyaltyBadge badge;

  const _BadgeCard({required this.badge});

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    final radius = context.radius;
    final iconSize = context.iconSize;
    final colorScheme = context.colorScheme;

    final earned = badge.isEarned;

    final categoryColor = _categoryColor(badge.category, colorScheme);

    final displayColor = earned ? categoryColor : colorScheme.onSurfaceVariant;

    final progress = (badge.progressPercent / 100).clamp(0.0, 1.0).toDouble();

    return Container(
      padding: EdgeInsets.all(spacing.md),
      decoration: BoxDecoration(
        color: context.theme.cardColor,
        borderRadius: BorderRadius.circular(radius.cardRadius),
        border: Border.all(
          color: earned
              ? categoryColor.withValues(alpha: 0.35)
              : colorScheme.outline.withValues(alpha: 0.15),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: EdgeInsets.all(spacing.sm),
                decoration: BoxDecoration(
                  color: displayColor.withValues(alpha: earned ? 0.15 : 0.08),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  earned ? _badgeIcon(badge.iconKey) : Icons.lock_rounded,
                  size: iconSize.medium,
                  color: displayColor,
                ),
              ),

              const Spacer(),

              if (earned)
                Icon(
                  Icons.check_circle_rounded,
                  size: iconSize.medium,
                  color: _BadgeColors.success,
                ),
            ],
          ),

          SizedBox(height: spacing.sm),

          Text(
            badge.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTextStyles.small(
              context,
            ).copyWith(fontWeight: FontWeight.w800),
          ),

          SizedBox(height: spacing.xs),

          Expanded(
            child: Text(
              badge.description,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyles.tiny(
                context,
              ).copyWith(color: colorScheme.onSurfaceVariant, height: 1.35),
            ),
          ),

          SizedBox(height: spacing.xs),

          Text(
            _categoryLabel(badge.category),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTextStyles.tiny(
              context,
            ).copyWith(color: displayColor, fontWeight: FontWeight.w700),
          ),

          SizedBox(height: spacing.sm),

          ClipRRect(
            borderRadius: BorderRadius.circular(radius.borderRadius),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: spacing.xs,
              color: displayColor,
              backgroundColor: colorScheme.outline.withValues(alpha: 0.14),
            ),
          ),

          SizedBox(height: spacing.xs),

          Text(
            earned
                ? 'Earned'
                : '${badge.currentValue} / '
                      '${badge.targetValue}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTextStyles.tinyNumber(context).copyWith(
              color: earned
                  ? _BadgeColors.success
                  : colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _RefreshableState extends StatelessWidget {
  final Widget child;

  const _RefreshableState({required this.child});

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

abstract final class _BadgeColors {
  static const gold = Color(0xFFD4AF37);

  static const darkGold = Color(0xFF8C6500);

  static const success = Color(0xFF19B76A);

  static const wallet = Color(0xFF2979FF);

  static const lending = Color(0xFF7657FF);

  static const community = Color(0xFF00897B);

  static const merchant = Color(0xFFF57C00);

  static const agent = Color(0xFF3F51B5);
}

Color _categoryColor(String category, ColorScheme colorScheme) {
  return switch (category.trim().toLowerCase()) {
    'wallet' => _BadgeColors.wallet,
    'gold' => _BadgeColors.gold,
    'lending' => _BadgeColors.lending,
    'community' => _BadgeColors.community,
    'merchant' => _BadgeColors.merchant,
    'agent' => _BadgeColors.agent,
    _ => colorScheme.onSurfaceVariant,
  };
}

String _categoryLabel(String category) {
  final value = category.trim();

  if (value.isEmpty) {
    return 'Other';
  }

  return value
      .split('_')
      .where((part) => part.isNotEmpty)
      .map(
        (part) =>
            '${part[0].toUpperCase()}'
            '${part.substring(1).toLowerCase()}',
      )
      .join(' ');
}

IconData _badgeIcon(String iconKey) {
  return switch (iconKey) {
    'account_balance_wallet' => Icons.account_balance_wallet_rounded,
    'swap_horiz' => Icons.swap_horiz_rounded,
    'storefront' => Icons.storefront_rounded,
    'diamond' => Icons.diamond_rounded,
    'savings' => Icons.savings_rounded,
    'verified' => Icons.verified_rounded,
    'groups' => Icons.groups_rounded,
    'stars' => Icons.stars_rounded,
    _ => Icons.military_tech_rounded,
  };
}
