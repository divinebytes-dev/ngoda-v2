import 'package:flutter/material.dart';

class NavItem {
  const NavItem({required this.destination, required this.route, this.action});

  final NavigationDestination destination;

  final String route;

  final VoidCallback? action;
}
