import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:ngoda/data_models/user/user_contact_details.dart';
import 'package:ngoda/services/dialog_service.dart';
import 'package:ngoda/ui/extensions/app_size.dart';
import 'package:ngoda/ui/extensions/theme_extension.dart';
import 'package:ngoda/ui/screens/customer/details/providers/user_contacts_provider.dart';
import 'package:ngoda/ui/screens/customer/details/providers/user_details_provider.dart';
import 'package:ngoda/ui/shared/app_text_styles.dart';
import 'package:ngoda/ui/widgets/app_button.dart';
import 'package:ngoda/ui/widgets/input_field.dart';
import 'package:ngoda/ui/widgets/view_header.dart';

class ContactDetailsScreen extends ConsumerStatefulWidget {
  final UserContactDetails? contactDetails;

  const ContactDetailsScreen({super.key, this.contactDetails});

  @override
  ConsumerState<ContactDetailsScreen> createState() =>
      _ContactDetailsScreenState();
}

class _ContactDetailsScreenState extends ConsumerState<ContactDetailsScreen> {
  final emailCtrl = TextEditingController();
  final phoneCtrl = TextEditingController();
  final countryCtrl = TextEditingController();
  final addressCtrl = TextEditingController();
  final cityCtrl = TextEditingController();
  final provinceCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();

    _initialiseContactDetails();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }

      ref
          .read(userContactsProvider.notifier)
          .initContact(widget.contactDetails);
    });
  }

  void _initialiseContactDetails() {
    final contact = widget.contactDetails;

    if (contact == null) {
      return;
    }

    emailCtrl.text = contact.email ?? '';
    phoneCtrl.text = contact.phone ?? '';
    countryCtrl.text = contact.countryName ?? '';
    addressCtrl.text = contact.residentialAddress ?? '';
    cityCtrl.text = contact.city ?? '';
    provinceCtrl.text = contact.provinceState ?? '';
  }

  @override
  void dispose() {
    emailCtrl.dispose();
    phoneCtrl.dispose();
    countryCtrl.dispose();
    addressCtrl.dispose();
    cityCtrl.dispose();
    provinceCtrl.dispose();

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(userContactsProvider);

    final notifier = ref.read(userContactsProvider.notifier);

    final spacing = context.spacing;
    final radius = context.radius;
    final colorScheme = context.colorScheme;

    return Scaffold(
      body: SafeArea(
        child: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTap: () {
            FocusScope.of(context).unfocus();
          },
          child: Padding(
            padding: EdgeInsets.all(spacing.margin),
            child: Column(
              children: [
                ViewHeader(
                  title: 'Contact Details',
                  onClose: () {
                    context.pop();
                  },
                ),

                SizedBox(height: spacing.md),

                Expanded(
                  child: SingleChildScrollView(
                    keyboardDismissBehavior:
                        ScrollViewKeyboardDismissBehavior.onDrag,
                    child: Container(
                      width: double.infinity,
                      padding: EdgeInsets.all(spacing.md),
                      decoration: BoxDecoration(
                        color: context.theme.cardColor,
                        borderRadius: BorderRadius.circular(radius.edgeInsert),
                        border: Border.all(
                          color: colorScheme.outlineVariant.withValues(
                            alpha: 0.09,
                          ),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Contact Information',
                            style: AppTextStyles.medium(
                              context,
                            ).copyWith(fontWeight: FontWeight.w600),
                          ),

                          SizedBox(height: spacing.lg),

                          InputField(
                            controller: emailCtrl,
                            placeholder: 'Email Address',
                            keyboardType: TextInputType.emailAddress,
                            onChanged: notifier.updateEmail,
                          ),

                          SizedBox(height: spacing.sm),

                          InputField(
                            controller: phoneCtrl,
                            placeholder: 'Phone Number',
                            keyboardType: TextInputType.phone,
                            onChanged: notifier.updatePhone,
                          ),

                          SizedBox(height: spacing.sm),

                          InputField(
                            controller: countryCtrl,
                            placeholder: 'Country',
                            keyboardType: TextInputType.text,
                            onChanged: notifier.updateCountryName,
                          ),

                          SizedBox(height: spacing.sm),

                          InputField(
                            controller: addressCtrl,
                            placeholder: 'Residential Address',
                            keyboardType: TextInputType.streetAddress,
                            onChanged: notifier.updateResidentialAddress,
                          ),

                          SizedBox(height: spacing.sm),

                          InputField(
                            controller: cityCtrl,
                            placeholder: 'City',
                            keyboardType: TextInputType.text,
                            onChanged: notifier.updateCity,
                          ),

                          SizedBox(height: spacing.sm),

                          InputField(
                            controller: provinceCtrl,
                            placeholder: 'Province / State',
                            keyboardType: TextInputType.text,
                            onChanged: notifier.updateProvinceState,
                          ),

                          if (state.error != null) ...[
                            SizedBox(height: spacing.sm),

                            Text(
                              state.error!,
                              style: AppTextStyles.small(
                                context,
                              ).copyWith(color: colorScheme.error),
                            ),
                          ],

                          SizedBox(height: spacing.lg),

                          Row(
                            children: [
                              Expanded(
                                child: AppButton(
                                  text: 'Cancel',
                                  isPrimary: false,
                                  isDisabled: state.isLoading,
                                  onPressed: () {
                                    context.pop();
                                  },
                                ),
                              ),

                              SizedBox(width: spacing.md),

                              Expanded(
                                child: AppButton(
                                  text: 'Update',
                                  isProcessing: state.isLoading,
                                  isDisabled: !state.isValid || state.isLoading,
                                  onPressed: !state.isValid || state.isLoading
                                      ? null
                                      : _handleUpdate,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _handleUpdate() async {
    FocusScope.of(context).unfocus();

    final state = ref.read(userContactsProvider);

    if (!state.isValid) {
      await DialogService.error(
        context,
        message: 'Please complete all required fields',
      );

      return;
    }

    try {
      await ref.read(userContactsProvider.notifier).updateUserContacts();

      if (!mounted) {
        return;
      }

      ref.invalidate(userDetailsProvider);

      await DialogService.success(
        context,
        message: 'Contact details updated successfully',
      );

      if (!mounted) {
        return;
      }

      context.pop();
    } catch (error) {
      if (!mounted) {
        return;
      }

      await DialogService.error(context, message: error.toString());
    }
  }
}
