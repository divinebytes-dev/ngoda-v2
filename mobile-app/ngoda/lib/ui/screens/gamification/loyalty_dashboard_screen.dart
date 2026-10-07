import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:ngoda/data_models/gamification/loyalty/loyalty_summary.dart';
import 'package:ngoda/data_models/params/loyalty_ledger_params.dart';
import 'package:ngoda/ui/extensions/app_size.dart';
import 'package:ngoda/ui/extensions/theme_extension.dart';
import 'package:ngoda/ui/screens/gamification/provider/loyalty_summary_provider.dart';
import 'package:ngoda/ui/shared/app_text_styles.dart';
import 'package:ngoda/ui/widgets/app_empty_state.dart';
import 'package:ngoda/ui/widgets/app_error_state.dart';
import 'package:ngoda/ui/widgets/app_loader.dart';
import 'package:ngoda/ui/widgets/view_header.dart';

class LoyaltyDashboardScreen extends ConsumerWidget {
  const LoyaltyDashboardScreen({super.key});

  Future<void> _refresh(WidgetRef ref) async {
    ref.invalidate(loyaltySummaryProvider);

    await ref.read(loyaltySummaryProvider.future);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summaryAsync = ref.watch(loyaltySummaryProvider);

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            ViewHeader(
              title: 'Ngoda Rewards',
              onClose: () {
                context.pop();
              },
            ),
            Expanded(
              child: RefreshIndicator(
                onRefresh: () {
                  return _refresh(ref);
                },
                child: summaryAsync.when(
                  loading: () => const AppLoader(
                    message: 'Loading rewards',
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

                    final summary = response.result;

                    if (summary == null) {
                      return const _RefreshableState(child: AppEmptyState());
                    }

                    return _LoyaltyDashboardContent(summary: summary);
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

class _LoyaltyDashboardContent extends StatelessWidget {
  final LoyaltySummary summary;

  const _LoyaltyDashboardContent({required this.summary});

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: EdgeInsets.fromLTRB(spacing.md, 0, spacing.md, spacing.xxl),
      children: [
        _LevelCard(summary: summary),
        SizedBox(height: spacing.md),
        _PointsOverview(summary: summary),
        SizedBox(height: spacing.sm),
        _RewardActionCard(
          icon: Icons.receipt_long_rounded,
          title: 'Points history',
          subtitle: 'View points earned, reversed, or adjusted',
          onTap: () {
            context.push(
              '/rewards/points-history',
              extra: const LoyaltyLedgerParams(),
            );
          },
        ),
        SizedBox(height: spacing.sm),
        _RewardActionCard(
          icon: Icons.military_tech_rounded,
          iconColor: _RewardColors.gold,
          title: 'Badges',
          subtitle: 'View earned badges and milestone progress',
          onTap: () {
            context.push('/rewards/badges');
          },
        ),
        SizedBox(height: spacing.md),
        const _PointsExplanationCard(),
      ],
    );
  }
}

class _LevelCard extends StatelessWidget {
  final LoyaltySummary summary;

  const _LevelCard({required this.summary});

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    final radius = context.radius;
    final iconSize = context.iconSize;

    final levelColor = _levelColor(summary.level.code);

    final progress = (summary.progress.percent / 100)
        .clamp(0.0, 1.0)
        .toDouble();

    final progressText = summary.progress.isHighestLevel
        ? 'Highest level achieved'
        : '${_formatPoints(summary.progress.pointsToNextLevel)} '
              'points to ${summary.nextLevel?.name ?? 'next level'}';

    return Container(
      padding: EdgeInsets.all(spacing.lg),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            levelColor,
            Color.lerp(levelColor, Colors.black, 0.32) ?? levelColor,
          ],
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
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.35),
                  ),
                ),
                child: Icon(
                  Icons.workspace_premium_rounded,
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
                      '${summary.level.name} Level',
                      style: AppTextStyles.medium(context).copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    SizedBox(height: spacing.xs),
                    Text(
                      progressText,
                      style: AppTextStyles.tiny(
                        context,
                      ).copyWith(color: Colors.white.withValues(alpha: 0.82)),
                    ),
                  ],
                ),
              ),
            ],
          ),
          SizedBox(height: spacing.xxl),
          Text(
            _formatPoints(summary.availablePoints),
            style: AppTextStyles.largeNumber(
              context,
            ).copyWith(color: Colors.white, fontWeight: FontWeight.w900),
          ),
          SizedBox(height: spacing.xs),
          Text(
            'Available points',
            style: AppTextStyles.tiny(
              context,
            ).copyWith(color: Colors.white.withValues(alpha: 0.78)),
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
          SizedBox(height: spacing.sm),
          Row(
            children: [
              Expanded(
                child: Text(
                  '${summary.progress.percent.toStringAsFixed(0)}% progress',
                  style: AppTextStyles.tiny(
                    context,
                  ).copyWith(color: Colors.white.withValues(alpha: 0.80)),
                ),
              ),
              Text(
                '${_formatPoints(summary.tierPoints)} tier points',
                style: AppTextStyles.tiny(
                  context,
                ).copyWith(color: Colors.white, fontWeight: FontWeight.w700),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PointsOverview extends StatelessWidget {
  final LoyaltySummary summary;

  const _PointsOverview({required this.summary});

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    final colorScheme = context.colorScheme;

    return Row(
      children: [
        Expanded(
          child: _StatCard(
            icon: Icons.trending_up_rounded,
            label: 'Tier points',
            value: _formatPoints(summary.tierPoints),
            color: colorScheme.primary,
          ),
        ),
        SizedBox(width: spacing.sm),
        Expanded(
          child: _StatCard(
            icon: Icons.auto_awesome_rounded,
            label: 'Lifetime earned',
            value: _formatPoints(summary.lifetimeEarnedPoints),
            color: _RewardColors.gold,
          ),
        ),
      ],
    );
  }
}

class _StatCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  const _StatCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    final radius = context.radius;
    final iconSize = context.iconSize;
    final colorScheme = context.colorScheme;

    return Container(
      padding: EdgeInsets.all(spacing.md),
      decoration: BoxDecoration(
        color: context.theme.cardColor,
        borderRadius: BorderRadius.circular(radius.cardRadius),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.09),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: iconSize.medium, color: color),
          SizedBox(height: spacing.md),
          Text(
            value,
            style: AppTextStyles.smallNumber(
              context,
            ).copyWith(fontWeight: FontWeight.w800),
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

class _RewardActionCard extends StatelessWidget {
  final IconData icon;
  final Color? iconColor;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _RewardActionCard({
    required this.icon,
    this.iconColor,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    final radius = context.radius;
    final iconSize = context.iconSize;
    final colorScheme = context.colorScheme;

    return Material(
      color: context.theme.cardColor,
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
              Container(
                padding: EdgeInsets.all(spacing.sm),
                decoration: BoxDecoration(
                  color: (iconColor ?? colorScheme.primary).withValues(
                    alpha: 0.12,
                  ),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  icon,
                  size: iconSize.medium,
                  color: iconColor ?? colorScheme.primary,
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
                      ).copyWith(fontWeight: FontWeight.w700),
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
                Icons.chevron_right_rounded,
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

class _PointsExplanationCard extends StatelessWidget {
  const _PointsExplanationCard();

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    final radius = context.radius;
    final iconSize = context.iconSize;

    return Container(
      padding: EdgeInsets.all(spacing.md),
      decoration: BoxDecoration(
        color: _RewardColors.gold.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(radius.cardRadius),
        border: Border.all(color: _RewardColors.gold.withValues(alpha: 0.22)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.info_outline_rounded,
            size: iconSize.medium,
            color: _RewardColors.gold,
          ),
          SizedBox(width: spacing.sm),
          Expanded(
            child: Text(
              'Available points can be used for rewards. '
              'Tier points measure your long-term progress '
              'and are not reduced when rewards are redeemed.',
              style: AppTextStyles.tiny(context).copyWith(height: 1.45),
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

abstract final class _RewardColors {
  static const gold = Color(0xFFD4AF37);

  static const silver = Color(0xFF8C98A4);

  static const platinum = Color(0xFF536878);

  static const diamond = Color(0xFF5B5BD6);

  static const bronze = Color(0xFF9A633A);
}

Color _levelColor(String code) {
  return switch (code.toLowerCase()) {
    'silver' => _RewardColors.silver,
    'gold' => _RewardColors.gold,
    'platinum' => _RewardColors.platinum,
    'diamond' => _RewardColors.diamond,
    _ => _RewardColors.bronze,
  };
}

String _formatPoints(int value) {
  return value.toString().replaceAllMapped(
    RegExp(r'\B(?=(\d{3})+(?!\d))'),
    (_) => ',',
  );
}
