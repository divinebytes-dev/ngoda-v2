import 'package:go_router/go_router.dart';

import 'package:ngoda/core/router/utils/custom_page_transition.dart';
import 'package:ngoda/data_models/admin/operational_country.dart';
import 'package:ngoda/data_models/currency/currency.dart';
import 'package:ngoda/ui/screens/admin/change-role/change_user_role_screen.dart';
import 'package:ngoda/ui/screens/admin/country/add_country_currency_screen.dart';
import 'package:ngoda/ui/screens/admin/country/add_country_screen.dart';
import 'package:ngoda/ui/screens/admin/country/admin_country_screen.dart';
import 'package:ngoda/ui/screens/admin/country/country_list_screen.dart';
import 'package:ngoda/ui/screens/admin/currency/add_supported_currency.dart';
import 'package:ngoda/ui/screens/admin/currency/admin_currency_screen.dart';
import 'package:ngoda/ui/screens/admin/currency/currency_list_screen.dart';
import 'package:ngoda/ui/screens/admin/grand-role/grand_role.dart';
import 'package:ngoda/ui/screens/admin/user_role_screen.dart';

final List<GoRoute> adminRoutes = [
  /*
   * User role administration.
   */
  GoRoute(
    path: '/user-role',
    builder: (_, _) => const UserRoleScreen(),
    routes: [
      GoRoute(
        path: 'change-role',
        pageBuilder: (_, state) {
          return slidePage(const ChangeUserRoleScreen(), state);
        },
      ),
      GoRoute(
        path: 'grant-role',
        pageBuilder: (_, state) {
          return slidePage(const GrantUserRoleScreen(), state);
        },
      ),
    ],
  ),

  /*
   * Country administration.
   */
  GoRoute(
    path: '/country',
    builder: (_, _) => const AdminCountryScreen(),
    routes: [
      GoRoute(
        path: 'operational-countries',
        pageBuilder: (_, state) {
          return slidePage(CountryListScreen(), state);
        },
      ),
      GoRoute(
        path: 'add-operational-country',
        pageBuilder: (_, state) {
          final country = state.extra is OperationalCountry
              ? state.extra as OperationalCountry
              : null;

          return slidePage(AddCountryScreen(country: country), state);
        },
      ),
      GoRoute(
        path: 'add-country-currency',
        pageBuilder: (_, state) {
          return slidePage(AddCountryCurrencyScreen(), state);
        },
      ),
    ],
  ),

  /*
   * Currency administration.
   */
  GoRoute(
    path: '/currency',
    builder: (_, _) => const AdminCurrencyScreen(),
    routes: [
      GoRoute(
        path: 'currency-list',
        pageBuilder: (_, state) {
          return slidePage(CurrencyListScreen(), state);
        },
      ),
      GoRoute(
        path: 'add-supported-currency',
        pageBuilder: (_, state) {
          final currency = state.extra is Currency
              ? state.extra as Currency
              : null;

          return slidePage(
            AddSupportedCurrencyScreen(currency: currency),
            state,
          );
        },
      ),
    ],
  ),
];
