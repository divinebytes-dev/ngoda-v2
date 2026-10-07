import 'package:go_router/go_router.dart';

import 'package:ngoda/core/router/utils/custom_page_transition.dart';
import 'package:ngoda/data_models/kyc/user_kyc_details.dart';
import 'package:ngoda/data_models/kyc/user_verification_details.dart';
import 'package:ngoda/data_models/user/user_basic_profile.dart';
import 'package:ngoda/data_models/user/user_contact_details.dart';
import 'package:ngoda/ui/screens/customer/details/basic_profile_screen.dart';
import 'package:ngoda/ui/screens/customer/details/contact_details_screen.dart';
import 'package:ngoda/ui/screens/customer/details/kyc_details_screen.dart';
import 'package:ngoda/ui/screens/customer/details/reset_password_screen.dart';
import 'package:ngoda/ui/screens/customer/details/verification_document_screen.dart';
import 'package:ngoda/ui/screens/more/more_screen.dart';
import 'package:ngoda/ui/screens/more/profile/profile_screen.dart';
import 'package:ngoda/ui/screens/more/security/change_pin_screen.dart';
import 'package:ngoda/ui/screens/more/security/security_screen.dart';
import 'package:ngoda/ui/widgets/dashboard_router.dart';

final List<GoRoute> commonRoutes = [
  GoRoute(path: '/user-dashboard', builder: (_, _) => const DashboardRouter()),

  GoRoute(
    path: '/more',
    pageBuilder: (_, state) {
      return slidePage(const MoreScreen(), state);
    },
  ),

  GoRoute(
    path: '/profile',
    pageBuilder: (_, state) {
      return slidePage(const ProfileScreen(), state);
    },
    routes: [
      GoRoute(
        path: 'basic-profile',
        pageBuilder: (_, state) {
          final data = state.extra as UserBasicProfile?;

          return slidePage(BasicProfileScreen(profile: data), state);
        },
      ),

      GoRoute(
        path: 'contact-details',
        pageBuilder: (_, state) {
          final data = state.extra as UserContactDetails?;

          return slidePage(ContactDetailsScreen(contactDetails: data), state);
        },
      ),

      GoRoute(
        path: 'kyc-details',
        pageBuilder: (_, state) {
          final data = state.extra as UserKycDetails?;

          return slidePage(KycDetailsScreen(kycDetails: data), state);
        },
      ),

      GoRoute(
        path: 'verification-documents',
        pageBuilder: (_, state) {
          final data = state.extra as UserVerificationDocuments?;

          return slidePage(
            VerificationDocumentsScreen(verificationDocuments: data),
            state,
          );
        },
      ),
    ],
  ),

  GoRoute(
    path: '/security',
    pageBuilder: (_, state) {
      return slidePage(const SecurityScreen(), state);
    },
    routes: [
      GoRoute(
        path: 'reset-password',
        pageBuilder: (_, state) {
          return slidePage(const ResetPasswordScreen(), state);
        },
      ),
      GoRoute(
        path: 'change-pin',
        pageBuilder: (_, state) {
          return slidePage(const ChangePinScreen(), state);
        },
      ),
    ],
  ),
];
