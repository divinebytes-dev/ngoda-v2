import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:internet_connection_checker_plus/internet_connection_checker_plus.dart';

import 'package:ngoda/ui/enums/enums.dart';

final networkConnectionProvider = StreamProvider<NetworkStatus>((ref) {
  final internetConnection = InternetConnection();

  late final StreamController<NetworkStatus> controller;

  StreamSubscription<InternetStatus>? subscription;

  controller = StreamController<NetworkStatus>(
    onListen: () async {
      final hasInternet = await internetConnection.hasInternetAccess;

      if (!controller.isClosed) {
        controller.add(
          hasInternet ? NetworkStatus.connected : NetworkStatus.disconnected,
        );
      }

      subscription = internetConnection.onStatusChange.listen((status) {
        if (controller.isClosed) {
          return;
        }

        controller.add(
          status == InternetStatus.connected
              ? NetworkStatus.connected
              : NetworkStatus.disconnected,
        );
      }, onError: controller.addError);
    },
  );

  ref.onDispose(() {
    subscription?.cancel();
    controller.close();
  });

  return controller.stream;
});
