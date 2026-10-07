import 'package:go_router/go_router.dart';

import 'package:ngoda/core/router/utils/custom_page_transition.dart';
import 'package:ngoda/data_models/kyc/user_kyc_details.dart';
import 'package:ngoda/data_models/kyc/user_verification_details.dart';
import 'package:ngoda/data_models/kyc/user_verification_document.dart';
import 'package:ngoda/data_models/user/user_details.dart';
import 'package:ngoda/ui/screens/compliance/kyc_decision_screen.dart';
import 'package:ngoda/ui/screens/compliance/kyc_document_viewer_screen.dart';
import 'package:ngoda/ui/screens/compliance/kyc_documents_screen.dart';
import 'package:ngoda/ui/screens/compliance/kyc_review_list_screen.dart';
import 'package:ngoda/ui/screens/compliance/kyc_review_screen.dart';
import 'package:ngoda/ui/screens/customer/details/kyc_details_screen.dart';

final List<GoRoute> complianceRoutes = [
  GoRoute(
    path: '/pending-kyc-review',
    pageBuilder: (_, state) {
      return slidePage(KycReviewListScreen(), state);
    },
    routes: [
      GoRoute(
        path: 'user-kyc-review',
        pageBuilder: (_, state) {
          final userId = state.extra as String;

          return slidePage(KycReviewScreen(userId: userId), state);
        },
        routes: [
          GoRoute(
            path: 'user-details',
            pageBuilder: (_, state) {
              final kycDetails = state.extra as UserKycDetails;

              return slidePage(KycDetailsScreen(kycDetails: kycDetails), state);
            },
          ),
          GoRoute(
            path: ':userId/documents',
            pageBuilder: (_, state) {
              final documents = state.extra as UserVerificationDocuments;

              return slidePage(KycDocumentsScreen(documents: documents), state);
            },
            routes: [
              GoRoute(
                path: 'view',
                pageBuilder: (_, state) {
                  final document = state.extra as UserVerificationDocument;

                  return slidePage(
                    KycDocumentViewerScreen(document: document),
                    state,
                  );
                },
              ),
            ],
          ),
          GoRoute(
            path: ':userId/decision',
            pageBuilder: (_, state) {
              final review = state.extra as UserDetails;

              return slidePage(KycDecisionScreen(review: review), state);
            },
          ),
        ],
      ),
    ],
  ),
];
