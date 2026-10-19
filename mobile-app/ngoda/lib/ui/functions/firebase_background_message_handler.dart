import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:logging/logging.dart';

import 'package:ngoda/firebase_options.dart' as development;
import 'package:ngoda/firebase_options_qa.dart' as qa;

final Logger _log = Logger('FirebaseBackgroundMessageHandler');

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  final options = kReleaseMode
      ? qa.DefaultFirebaseOptions.currentPlatform
      : development.DefaultFirebaseOptions.currentPlatform;

  if (Firebase.apps.isEmpty) {
    await Firebase.initializeApp(options: options);
  }

  final app = Firebase.app();

  if (app.options.projectId != options.projectId ||
      app.options.appId != options.appId) {
    throw StateError(
      'Background Firebase configuration does not '
      'match the selected environment.',
    );
  }

  _log.info('Background message received: ${message.messageId}');
}

// import 'package:firebase_messaging/firebase_messaging.dart';
// import 'package:logging/logging.dart';

// final Logger _log = Logger('FirebaseBackgroundMessageHandler');

// Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
//   _log.info(
//     'Background message received: '
//     '${message.messageId}',
//   );

//   _log.fine(
//     'Background message data: '
//     '${message.data}',
//   );
// }
