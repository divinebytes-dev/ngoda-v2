import 'package:flutter/material.dart';
import 'package:ngoda/ui/extensions/theme_extension.dart';
import 'package:ngoda/ui/widgets/app_state_view.dart';

class AppEmptyState extends StatelessWidget {
  final String title;
  final String? message;
  final IconData icon;
  final Widget? action;

  const AppEmptyState({
    super.key,
    this.title = 'No Data',
    this.message,
    this.icon = Icons.inbox_outlined,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    return AppStateView(
      title: title,
      message: message,
      icon: icon,
      iconColor: context.colorScheme.primary,
      action: action,
    );
  }
}
