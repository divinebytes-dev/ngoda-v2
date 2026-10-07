import 'package:flutter/material.dart';
import 'package:ngoda/ui/widgets/app_screen_header.dart';

class ScreenHeader extends StatelessWidget {
  final String title;
  final String? subtitle;

  const ScreenHeader({super.key, required this.title, this.subtitle});

  @override
  Widget build(BuildContext context) {
    return AppScreenHeader(title: title, subtitle: subtitle);
  }
}
