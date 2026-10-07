import 'dart:async';

import 'package:flutter/material.dart';
import 'package:ngoda/ui/extensions/app_size.dart';

class AnimatedDots extends StatefulWidget {
  final Color color;

  /// Optional explicit dot size.
  ///
  /// When null, the application design system determines
  /// the appropriate size.
  final double? size;

  const AnimatedDots({super.key, required this.color, this.size});

  @override
  State<AnimatedDots> createState() {
    return _AnimatedDotsState();
  }
}

class _AnimatedDotsState extends State<AnimatedDots> {
  static const int _dotCount = 3;

  static const Duration _interval = Duration(milliseconds: 350);

  Timer? _timer;

  int _visibleDots = 0;

  @override
  void initState() {
    super.initState();

    _timer = Timer.periodic(_interval, (_) {
      if (!mounted) {
        return;
      }

      setState(() {
        _visibleDots = (_visibleDots + 1) % (_dotCount + 1);
      });
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    final iconSize = context.iconSize;

    final dotSize = widget.size ?? (iconSize.small * 0.375);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(_dotCount, (index) {
        final isVisible = index < _visibleDots;

        final isNewest = index == _visibleDots - 1;

        return Padding(
          padding: EdgeInsets.symmetric(horizontal: spacing.xs / 2),
          child: AnimatedOpacity(
            opacity: isVisible ? 1 : 0,
            duration: _interval,
            curve: Curves.easeOut,
            child: AnimatedScale(
              scale: isNewest ? 1.2 : 1,
              duration: _interval,
              curve: Curves.easeOutBack,
              child: Container(
                width: dotSize,
                height: dotSize,
                decoration: BoxDecoration(
                  color: widget.color,
                  shape: BoxShape.circle,
                ),
              ),
            ),
          ),
        );
      }),
    );
  }
}
