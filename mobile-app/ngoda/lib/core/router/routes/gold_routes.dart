import 'package:go_router/go_router.dart';

import 'package:ngoda/core/router/utils/custom_page_transition.dart';
import 'package:ngoda/ui/screens/wallet/gold/buy/buy_gold_screen.dart';
import 'package:ngoda/ui/screens/wallet/gold/gold_screen.dart';
import 'package:ngoda/ui/screens/wallet/gold/sell/sell_gold_screen.dart';
import 'package:ngoda/ui/screens/wallet/gold/transfer/transfer_gold_screen.dart';

final List<GoRoute> goldRoutes = [
  GoRoute(
    path: '/gold',
    builder: (_, _) => const GoldScreen(),
    routes: [
      GoRoute(
        path: 'buy',
        pageBuilder: (_, state) {
          return slidePage(BuyGoldScreen(), state);
        },
      ),
      GoRoute(
        path: 'transfer',
        pageBuilder: (_, state) {
          return slidePage(TransferGoldScreen(), state);
        },
      ),
      GoRoute(
        path: 'sell',
        pageBuilder: (_, state) {
          return slidePage(SellGoldScreen(), state);
        },
      ),
    ],
  ),
];
