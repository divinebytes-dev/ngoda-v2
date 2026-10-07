import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:ngoda/ui/extensions/app_size.dart';
import 'package:ngoda/ui/extensions/theme_extension.dart';
import 'package:ngoda/ui/functions/get_current_user.dart';
import 'package:ngoda/ui/screens/customer/details/providers/user_details_provider.dart';
import 'package:ngoda/ui/shared/app_text_styles.dart';
import 'package:ngoda/ui/widgets/app_error_state.dart';
import 'package:ngoda/ui/widgets/app_loader.dart';
import 'package:ngoda/ui/widgets/view_header.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final spacing = context.spacing;

    final userDetailsAsync = ref.watch(userDetailsProvider);

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: EdgeInsets.all(spacing.margin),
          child: Column(
            children: [
              ViewHeader(
                title: 'Profile',
                onClose: () {
                  context.pop();
                },
              ),

              SizedBox(height: spacing.md),

              Expanded(
                child: userDetailsAsync.when(
                  loading: () {
                    return const AppLoader(
                      message: 'Loading profile',
                      fullScreen: false,
                    );
                  },

                  error: (error, stackTrace) {
                    return AppErrorState(message: error.toString());
                  },

                  data: (response) {
                    if (response.error != null) {
                      return AppErrorState(message: response.error!);
                    }

                    final userDetails = response.result;

                    if (userDetails == null) {
                      return const AppErrorState(
                        message: 'Unable to load profile details',
                      );
                    }

                    return RefreshIndicator(
                      onRefresh: () async {
                        ref.invalidate(userDetailsProvider);

                        await ref.read(userDetailsProvider.future);
                      },
                      child: SingleChildScrollView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        child: _ProfileContent(userDetails: userDetails),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProfileContent extends StatelessWidget {
  const _ProfileContent({required this.userDetails});

  final dynamic userDetails;

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    final radius = context.radius;
    final iconSize = context.iconSize;
    final colorScheme = context.colorScheme;

    final user = getCurrentUser();

    final email = user.email?.trim() ?? '';

    final role = user.role?.trim() ?? '';

    final fullName = userDetails.fullName.toString().trim();

    final displayName = fullName.isNotEmpty
        ? fullName
        : email.isNotEmpty
        ? email
        : 'Ngoda User';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          padding: EdgeInsets.all(spacing.lg),
          decoration: BoxDecoration(
            color: context.theme.cardColor,
            borderRadius: BorderRadius.circular(radius.edgeInsert),
            border: Border.all(
              color: colorScheme.outlineVariant.withValues(alpha: 0.09),
            ),
          ),
          child: Column(
            children: [
              Container(
                padding: EdgeInsets.all(spacing.md),
                decoration: BoxDecoration(
                  color: colorScheme.primary.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.person_outline,
                  size: iconSize.large,
                  color: colorScheme.primary,
                ),
              ),

              SizedBox(height: spacing.md),

              Text(
                displayName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: AppTextStyles.medium(
                  context,
                ).copyWith(fontWeight: FontWeight.w700),
              ),

              if (email.isNotEmpty && displayName != email) ...[
                SizedBox(height: spacing.xs),
                Text(
                  email,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: AppTextStyles.small(
                    context,
                  ).copyWith(color: colorScheme.onSurfaceVariant),
                ),
              ],

              if (role.isNotEmpty) ...[
                SizedBox(height: spacing.xs),
                Text(
                  role,
                  style: AppTextStyles.small(
                    context,
                  ).copyWith(color: colorScheme.onSurfaceVariant),
                ),
              ],
            ],
          ),
        ),

        SizedBox(height: spacing.md),

        _ProfileSection(
          title: 'Personal information',
          children: [
            _ProfileTile(
              icon: Icons.person_outline,
              title: 'Basic profile',
              subtitle: 'Manage your personal information',
              onTap: () {
                context.push(
                  '/profile/basic-profile',
                  extra: userDetails.basicProfile,
                );
              },
            ),
            SizedBox(height: spacing.md),
            _ProfileTile(
              icon: Icons.contact_phone_outlined,
              title: 'Contact details',
              subtitle: 'Manage your contact and address information',
              onTap: () {
                context.push(
                  '/profile/contact-details',
                  extra: userDetails.contactDetails,
                );
              },
            ),
          ],
        ),

        SizedBox(height: spacing.md),

        _ProfileSection(
          title: 'Verification',
          children: [
            _ProfileTile(
              icon: Icons.verified_user_outlined,
              title: 'KYC details',
              subtitle: 'View or update your KYC information',
              onTap: () {
                context.push(
                  '/profile/kyc-details',
                  extra: userDetails.kycDetails,
                );
              },
            ),

            SizedBox(height: spacing.sm),
            _ProfileTile(
              icon: Icons.description_outlined,
              title: 'Verification documents',
              subtitle: 'Manage your verification documents',
              onTap: () {
                context.push(
                  '/profile/verification-documents',
                  extra: userDetails.verificationDocuments,
                );
              },
            ),
          ],
        ),

        SizedBox(height: spacing.md),
      ],
    );
  }
}

class _ProfileSection extends StatelessWidget {
  const _ProfileSection({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    final radius = context.radius;
    final colorScheme = context.colorScheme;

    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(spacing.md),
      decoration: BoxDecoration(
        color: context.theme.cardColor,
        borderRadius: BorderRadius.circular(radius.edgeInsert),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.09),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: AppTextStyles.small(context).copyWith(
              color: colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
          ),

          SizedBox(height: spacing.sm),

          ...children,
        ],
      ),
    );
  }
}

class _ProfileTile extends StatelessWidget {
  const _ProfileTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    final radius = context.radius;
    final iconSize = context.iconSize;
    final colorScheme = context.colorScheme;

    return Material(
      color: Theme.of(context).cardColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(radius.borderRadius),
        side: BorderSide(
          color: colorScheme.outlineVariant.withValues(alpha: 0.09),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(radius.borderRadius),
        child: Padding(
          padding: EdgeInsets.all(spacing.md),
          child: Row(
            children: [
              Container(
                padding: EdgeInsets.all(spacing.sm),
                decoration: BoxDecoration(
                  color: colorScheme.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(radius.borderRadius),
                ),
                child: Icon(
                  icon,
                  size: iconSize.medium,
                  color: colorScheme.primary,
                ),
              ),

              SizedBox(width: spacing.md),

              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: AppTextStyles.small(
                        context,
                      ).copyWith(fontWeight: FontWeight.w600),
                    ),

                    SizedBox(height: spacing.xs),

                    Text(
                      subtitle,
                      style: AppTextStyles.tiny(
                        context,
                      ).copyWith(color: colorScheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),

              SizedBox(width: spacing.sm),

              Icon(
                Icons.chevron_right,
                size: iconSize.medium,
                color: colorScheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
