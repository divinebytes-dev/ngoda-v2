import 'package:flutter/material.dart';
import 'package:ngoda/services/number_format_service.dart';
import 'package:ngoda/ui/extensions/app_size.dart';
import 'package:ngoda/ui/shared/app_text_styles.dart';

class NetPositionCard extends StatefulWidget {
  final double amount;

  const NetPositionCard({super.key, required this.amount});

  @override
  State<NetPositionCard> createState() {
    return _NetPositionCardState();
  }
}

class _NetPositionCardState extends State<NetPositionCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );

    _setAnimation(begin: 0, end: widget.amount);

    _controller.forward();
  }

  void _setAnimation({required double begin, required double end}) {
    _animation = Tween<double>(
      begin: begin,
      end: end,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));
  }

  @override
  void didUpdateWidget(covariant NetPositionCard oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.amount == widget.amount) {
      return;
    }

    _setAnimation(begin: _animation.value, end: widget.amount);

    _controller.forward(from: 0);
  }

  @override
  void dispose() {
    _controller.dispose();

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    final radius = context.radius;
    final iconSize = context.iconSize;

    final isPositive = widget.amount >= 0;

    return Container(
      padding: EdgeInsets.all(spacing.lg),
      decoration: BoxDecoration(
        color: Colors.purple.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(radius.cardRadius),
        border: Border.all(color: Colors.purple.withValues(alpha: 0.15)),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                'Net Position',
                style: AppTextStyles.small(
                  context,
                ).copyWith(color: Colors.grey.shade600),
              ),
              SizedBox(width: spacing.xs),
              Icon(
                isPositive ? Icons.trending_up : Icons.trending_down,
                size: iconSize.small,
                color: isPositive ? Colors.green : Colors.red,
              ),
            ],
          ),
          SizedBox(height: spacing.xs),
          AnimatedBuilder(
            animation: _animation,
            builder: (context, child) {
              return Text(
                NumberFormatService.formatUsd(_animation.value),
                style: AppTextStyles.veryLargeNumber(
                  context,
                ).copyWith(color: Colors.purple, fontWeight: FontWeight.w700),
              );
            },
          ),
        ],
      ),
    );
  }
}
