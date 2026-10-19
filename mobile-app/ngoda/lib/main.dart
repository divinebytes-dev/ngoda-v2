import 'dart:developer' as dev;

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
import 'package:ngoda/firebase_options.dart' as development;
import 'package:ngoda/firebase_options_qa.dart' as qa;
import 'package:ngoda/services/hive_service.dart';
import 'package:ngoda/ui/functions/app_reset.dart';
import 'package:ngoda/ui/functions/firebase_background_message_handler.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  _configureLogging();

  final log = Logger('main');

  // Until production configuration is added,
  // release builds connect to QA.
  const isQa = kReleaseMode;
  const environmentName = isQa ? 'QA' : 'Development';
  const environmentFile = isQa ? '.env.qa' : '.env';

  log.info('Initialising $environmentName application');

  await dotenv.load(fileName: environmentFile);

  final supabaseUrl = _requiredSetting('NEXT_PUBLIC_SUPABASE_URL');

  final publishableKey = _requiredSetting(
    'NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY',
  );

  _validateSupabaseUrl(supabaseUrl, isQa: isQa);

  final firebaseOptions = isQa
      ? qa.DefaultFirebaseOptions.currentPlatform
      : development.DefaultFirebaseOptions.currentPlatform;

  await _initializeFirebase(firebaseOptions, log);

  FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

  final hiveService = HiveService();

  await hiveService.init();

  await Supabase.initialize(url: supabaseUrl, publishableKey: publishableKey);

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

String _requiredSetting(String name) {
  final value = dotenv.env[name]?.trim();

  if (value == null || value.isEmpty) {
    throw StateError('Missing application configuration: $name');
  }

  return value;
}

void _validateSupabaseUrl(String value, {required bool isQa}) {
  final uri = Uri.tryParse(value);

  final expectedHost = isQa
      ? 'xbqbpmeiidsgnhqfychi.supabase.co'
      : 'idjrocijzljmgvvartzq.supabase.co';

  if (uri == null ||
      uri.scheme != 'https' ||
      uri.host != expectedHost ||
      uri.userInfo.isNotEmpty ||
      uri.hasPort ||
      (uri.path.isNotEmpty && uri.path != '/') ||
      uri.hasQuery ||
      uri.hasFragment) {
    throw StateError('Supabase URL does not match the selected environment.');
  }
}

Future<void> _initializeFirebase(FirebaseOptions options, Logger log) async {
  if (Firebase.apps.isEmpty) {
    await Firebase.initializeApp(options: options);
  }

  final app = Firebase.app();

  if (app.options.projectId != options.projectId ||
      app.options.appId != options.appId) {
    throw StateError(
      'Firebase configuration does not match '
      'the selected environment.',
    );
  }

  log.info('Firebase initialised: ${app.options.projectId}');
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

// import 'dart:developer' as dev;
// import 'dart:io';

// import 'package:firebase_core/firebase_core.dart';
// import 'package:firebase_messaging/firebase_messaging.dart';
// import 'package:flutter/foundation.dart';
// import 'package:flutter/material.dart';
// import 'package:flutter_dotenv/flutter_dotenv.dart';
// import 'package:flutter_riverpod/flutter_riverpod.dart';
// import 'package:logging/logging.dart';
// import 'package:supabase_flutter/supabase_flutter.dart';

// import 'package:ngoda/app_initializer.dart';
// import 'package:ngoda/core/providers/hive_service_provider.dart';
// import 'package:ngoda/core/router/app_router.dart';
// import 'package:ngoda/firebase_options.dart';
// import 'package:ngoda/services/hive_service.dart';
// import 'package:ngoda/ui/functions/app_reset.dart';
// import 'package:ngoda/ui/functions/firebase_background_message_handler.dart';

// Future<void> main() async {
//   WidgetsFlutterBinding.ensureInitialized();

//   _configureLogging();

//   final log = Logger('main');

//   log.fine('Initialising application');

//   await _initializeFirebase(log);

//   await dotenv.load(fileName: '.env');

//   final hiveService = HiveService();

//   await hiveService.init();

//   await Supabase.initialize(
//     url: dotenv.env['NEXT_PUBLIC_SUPABASE_URL']!,
//     publishableKey: dotenv.env['NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY']!,
//   );

//   FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

//   runApp(
//     ValueListenableBuilder<int>(
//       valueListenable: appResetKey,
//       builder: (context, key, child) {
//         return ProviderScope(
//           key: ValueKey(key),
//           overrides: [hiveServiceProvider.overrideWithValue(hiveService)],
//           child: AppInitializer(navigatorKey: navigatorKey),
//         );
//       },
//     ),
//   );
// }

// void _configureLogging() {
//   Logger.root.level = kDebugMode ? Level.FINE : Level.INFO;

//   Logger.root.onRecord.listen((record) {
//     dev.log(
//       record.message,
//       time: record.time,
//       level: record.level.value,
//       name: record.loggerName,
//     );
//   });
// }

// Future<void> _initializeFirebase(Logger log) async {
//   if (Platform.isWindows) {
//     log.fine('Initialising Firebase for Windows');

//     await Firebase.initializeApp();

//     return;
//   }

//   if (Firebase.apps.isNotEmpty) {
//     log.fine('Firebase already initialised');

//     return;
//   }

//   log.fine('Initialising Firebase');

//   await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
// }
