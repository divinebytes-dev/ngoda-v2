import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AuthRecoveryListenerService extends StatefulWidget {
  final Widget child;

  const AuthRecoveryListenerService({super.key, required this.child});

  @override
  State<AuthRecoveryListenerService> createState() {
    return _AuthRecoveryListenerState();
  }
}

class _AuthRecoveryListenerState extends State<AuthRecoveryListenerService> {
  StreamSubscription<AuthState>? _authSubscription;

  bool _isHandlingRecovery = false;

  @override
  void initState() {
    super.initState();

    _authSubscription = Supabase.instance.client.auth.onAuthStateChange.listen(
      _handleAuthChange,
    );
  }

  void _handleAuthChange(AuthState authState) {
    if (authState.event != AuthChangeEvent.passwordRecovery) {
      return;
    }

    if (authState.session == null) {
      return;
    }

    if (!mounted || _isHandlingRecovery) {
      return;
    }

    _isHandlingRecovery = true;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }

      context.go('/new-password');
    });
  }

  @override
  void dispose() {
    _authSubscription?.cancel();

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}
