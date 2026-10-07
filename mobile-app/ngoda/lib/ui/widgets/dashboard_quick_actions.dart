import 'package:flutter/material.dart';
import 'package:ngoda/ui/extensions/app_size.dart';
import 'package:ngoda/ui/shared/app_text_styles.dart';

class DashboardQuickActions extends StatelessWidget {
  const DashboardQuickActions({super.key, required this.quickLinks});

  final List<Widget> quickLinks;

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Quick actions',
          style: AppTextStyles.tiny(
            context,
          ).copyWith(fontWeight: FontWeight.w700),
        ),
        SizedBox(height: spacing.sm),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (var index = 0; index < quickLinks.length; index++) ...[
                quickLinks[index],
                if (index < quickLinks.length - 1) SizedBox(width: spacing.sm),
              ],
            ],
          ),
        ),
      ],
    );
  }
}
