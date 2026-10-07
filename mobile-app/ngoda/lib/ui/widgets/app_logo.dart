import 'package:flutter/material.dart';
import 'package:ngoda/ui/extensions/app_size.dart';
import 'package:ngoda/ui/shared/app_text_styles.dart';

class AppLogo extends StatelessWidget {
  const AppLogo({super.key});

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;

    final brandStyle = AppTextStyles.brandTitle(context);

    return Semantics(
      label: 'Ngoda',
      child: ExcludeSemantics(
        child: RichText(
          text: TextSpan(
            style: brandStyle,
            children: [
              const TextSpan(text: 'NG'),

              WidgetSpan(
                alignment: PlaceholderAlignment.middle,
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: spacing.xs / 2),
                  child: Icon(
                    Icons.monetization_on_outlined,
                    size: brandStyle.fontSize,
                    color: brandStyle.color,
                  ),
                ),
              ),

              const TextSpan(text: 'DA'),
            ],
          ),
        ),
      ),
    );
  }
}
