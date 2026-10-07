import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:ngoda/ui/extensions/app_size.dart';
import 'package:ngoda/ui/extensions/theme_extension.dart';
import 'package:ngoda/ui/screens/customer/details/providers/user_details_provider.dart';
import 'package:ngoda/ui/widgets/action_tile.dart';
import 'package:ngoda/ui/widgets/app_error_state.dart';
import 'package:ngoda/ui/widgets/app_loader.dart';
import 'package:ngoda/ui/widgets/view_header.dart';

class UserDetailsScreen extends ConsumerWidget {
  const UserDetailsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final spacing = context.spacing;
    final colorScheme = context.colorScheme;

    final asyncData = ref.watch(userDetailsProvider);

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            ViewHeader(title: 'User Details', onClose: context.pop),
            Expanded(
              child: asyncData.when(
                loading: () {
                  return const AppLoader(
                    message: 'Loading your details',
                    fullScreen: false,
                  );
                },
                error: (error, stackTrace) {
                  return AppErrorState(message: error.toString());
                },
                data: (response) {
                  if (response.error != null) {
                    return AppErrorState(message: response.error.toString());
                  }

                  final details = response.result;

                  return ListView(
                    padding: EdgeInsets.all(spacing.lg),
                    children: [
                      ActionTile(
                        title: 'Basic Profile',
                        subtitle: 'Name, date of birth, gender and nationality',
                        icon: Icons.person_outline,
                        color: colorScheme.primary,
                        onTap: () {
                          context.push(
                            '/profile/user-details/basic-profile',
                            extra: details?.basicProfile,
                          );
                        },
                      ),
                      SizedBox(height: spacing.md),
                      ActionTile(
                        title: 'Contact Details',
                        subtitle: 'Email, phone number and residential address',
                        icon: Icons.contact_phone_outlined,
                        color: colorScheme.secondary,
                        onTap: () {
                          context.push(
                            '/profile/user-details/contact-details',
                            extra: details?.contactDetails,
                          );
                        },
                      ),
                      // SizedBox(height: spacing.md),
                      // ActionTile(
                      //   title: 'KYC Details',
                      //   subtitle: 'Identity, occupation and source of funds',
                      //   icon: Icons.verified_user_outlined,
                      //   color: colorScheme.tertiary,
                      //   onTap: () {
                      //     context.push(
                      //       '/profile/user-details/kyc-details',
                      //       extra: details?.kycDetails,
                      //     );
                      //   },
                      // ),
                      // SizedBox(height: spacing.md),
                      // ActionTile(
                      //   title: 'Verification Documents',
                      //   subtitle:
                      //       'Identity document, proof of address and selfie',
                      //   icon: Icons.document_scanner_outlined,
                      //   color: colorScheme.primary,
                      //   onTap: () {
                      //     context.push(
                      //       '/profile/user-details/verification-documents',
                      //       extra: details?.verificationDocuments,
                      //     );
                      //   },
                      // ),
                      // SizedBox(height: spacing.md),
                      // ActionTile(
                      //   title: 'Reset Password',
                      //   subtitle: 'Change your account password',
                      //   icon: Icons.lock_reset,
                      //   color: colorScheme.secondary,
                      //   onTap: () {
                      //     context.push('/profile/user-details/reset-password');
                      //   },
                      // ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
