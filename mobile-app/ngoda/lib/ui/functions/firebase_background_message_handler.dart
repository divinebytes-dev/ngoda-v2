import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:logging/logging.dart';

final Logger _log = Logger('FirebaseBackgroundMessageHandler');

Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  _log.info(
    'Background message received: '
    '${message.messageId}',
  );

  _log.fine(
    'Background message data: '
    '${message.data}',
  );
}
