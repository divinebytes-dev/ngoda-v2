import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:ngoda/services/notification_service.dart';

final notificationServiceProvider = Provider<NotificationService>((ref) {
  final service = NotificationService(supabase: Supabase.instance.client);
  ref.onDispose(() { unawaited(service.dispose()); });
  return service;
});
