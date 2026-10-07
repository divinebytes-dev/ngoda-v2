import 'package:flutter/material.dart';

import 'package:ngoda/ui/extensions/app_size.dart';
import 'package:ngoda/ui/extensions/theme_extension.dart';
import 'package:ngoda/ui/shared/app_text_styles.dart';

class PaymentCalculationCard extends StatelessWidget {
  final List<Widget> children;
  final String? error;

  const PaymentCalculationCard({super.key, required this.children, this.error});

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    final radius = context.radius;
    final iconSize = context.iconSize;
    final colorScheme = context.colorScheme;

    final hasError = error != null && error!.trim().isNotEmpty;

    return Container(
      margin: EdgeInsets.only(top: spacing.sm),
      padding: EdgeInsets.all(spacing.padding),
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        borderRadius: BorderRadius.circular(radius.borderRadius),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ...children,

          if (hasError) ...[
            SizedBox(height: spacing.sm),

            Container(
              width: double.infinity,
              padding: EdgeInsets.all(spacing.sm),
              decoration: BoxDecoration(
                color: colorScheme.error.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(radius.borderRadius),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.error_outline,
                    color: colorScheme.error,
                    size: iconSize.small,
                  ),

                  SizedBox(width: spacing.sm),

                  Expanded(
                    child: Text(
                      error!,
                      style: AppTextStyles.small(context).copyWith(
                        color: colorScheme.error,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
