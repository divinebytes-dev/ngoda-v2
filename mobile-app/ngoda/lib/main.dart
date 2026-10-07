import 'dart:developer' as dev;
import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:logging/logging.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:ngoda/app_initializer.dart';
import 'package:ngoda/core/providers/hive_service_provider.dart';
import 'package:ngoda/core/router/app_router.dart';
import 'package:ngoda/firebase_options.dart';
import 'package:ngoda/services/hive_service.dart';
import 'package:ngoda/ui/functions/app_reset.dart';
import 'package:ngoda/ui/functions/firebase_background_message_handler.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  _configureLogging();

  final log = Logger('main');

  log.fine('Initialising application');

  await _initializeFirebase(log);

  await dotenv.load(fileName: '.env');

  final hiveService = HiveService();

  await hiveService.init();

  await Supabase.initialize(
    url: dotenv.env['NEXT_PUBLIC_SUPABASE_URL']!,
    publishableKey: dotenv.env['NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY']!,
  );

  FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

  runApp(
    ValueListenableBuilder<int>(
      valueListenable: appResetKey,
      builder: (context, key, child) {
        return ProviderScope(
          key: ValueKey(key),
          overrides: [hiveServiceProvider.overrideWithValue(hiveService)],
          child: AppInitializer(navigatorKey: navigatorKey),
        );
      },
    ),
  );
}

void _configureLogging() {
  Logger.root.level = kDebugMode ? Level.FINE : Level.INFO;

  Logger.root.onRecord.listen((record) {
    dev.log(
      record.message,
      time: record.time,
      level: record.level.value,
      name: record.loggerName,
    );
  });
}

Future<void> _initializeFirebase(Logger log) async {
  if (Platform.isWindows) {
    log.fine('Initialising Firebase for Windows');

    await Firebase.initializeApp();

    return;
  }

  if (Firebase.apps.isNotEmpty) {
    log.fine('Firebase already initialised');

    return;
  }

  log.fine('Initialising Firebase');

  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
}
