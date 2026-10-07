import 'package:flutter/material.dart';
import 'package:ngoda/ui/widgets/app_screen_header.dart';

class ViewHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  final VoidCallback onClose;

  const ViewHeader({
    super.key,
    required this.title,
    this.subtitle,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    return AppScreenHeader(title: title, subtitle: subtitle, onClose: onClose);
  }
}
