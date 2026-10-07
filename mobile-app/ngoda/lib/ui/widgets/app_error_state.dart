import 'package:flutter/material.dart';
import 'package:ngoda/ui/extensions/app_size.dart';
import 'package:ngoda/ui/extensions/theme_extension.dart';
import 'package:ngoda/ui/widgets/app_button.dart';
import 'package:ngoda/ui/widgets/app_state_view.dart';

class AppErrorState extends StatelessWidget {
  final String title;
  final String? message;
  final String buttonText;
  final VoidCallback? onAction;
  final IconData icon;

  const AppErrorState({
    super.key,
    this.title = 'Error',
    this.message,
    this.buttonText = 'Go Back',
    this.onAction,
    this.icon = Icons.error_outline_rounded,
  });

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    final colorScheme = context.colorScheme;

    return AppStateView(
      title: title,
      message: message,
      icon: icon,
      iconColor: colorScheme.error,
      action: onAction == null
          ? null
          : SizedBox(
              width: spacing.buttonWidth,
              child: AppButton(text: buttonText, onPressed: onAction),
            ),
    );
  }
}
