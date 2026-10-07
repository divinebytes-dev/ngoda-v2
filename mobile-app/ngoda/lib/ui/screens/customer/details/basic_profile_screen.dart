import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:ngoda/data_models/user/user_basic_profile.dart';
import 'package:ngoda/services/dialog_service.dart';
import 'package:ngoda/ui/enums/enums.dart';
import 'package:ngoda/ui/extensions/app_size.dart';
import 'package:ngoda/ui/extensions/theme_extension.dart';
import 'package:ngoda/ui/screens/customer/details/providers/user_details_provider.dart';
import 'package:ngoda/ui/screens/customer/details/providers/user_details_transaction_provider.dart';
import 'package:ngoda/ui/shared/app_text_styles.dart';
import 'package:ngoda/ui/widgets/app_button.dart';
import 'package:ngoda/ui/widgets/app_search_dropdown_field.dart';
import 'package:ngoda/ui/widgets/date_time_input.dart';
import 'package:ngoda/ui/widgets/input_field.dart';
import 'package:ngoda/ui/widgets/view_header.dart';

class BasicProfileScreen extends ConsumerStatefulWidget {
  final UserBasicProfile? profile;

  const BasicProfileScreen({super.key, this.profile});

  @override
  ConsumerState<BasicProfileScreen> createState() => _BasicProfileScreenState();
}

class _BasicProfileScreenState extends ConsumerState<BasicProfileScreen> {
  final firstNameCtrl = TextEditingController();
  final middleNameCtrl = TextEditingController();
  final surnameCtrl = TextEditingController();
  final dateOfBirthCtrl = TextEditingController();
  final nationalityCtrl = TextEditingController();

  GenderType? gender;
  DateTime? selectedDateOfBirth;

  @override
  void initState() {
    super.initState();

    _initialiseProfile();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }

      ref
          .read(userDetailsTransactionProvider.notifier)
          .initBasicProfile(widget.profile);
    });
  }

  void _initialiseProfile() {
    final profile = widget.profile;

    if (profile == null) {
      return;
    }

    firstNameCtrl.text = profile.firstName ?? '';
    middleNameCtrl.text = profile.middleName ?? '';
    surnameCtrl.text = profile.surname ?? '';
    nationalityCtrl.text = profile.nationality ?? '';

    gender = profile.gender;
    selectedDateOfBirth = profile.dateOfBirth;

    if (selectedDateOfBirth != null) {
      dateOfBirthCtrl.text = _formatDate(selectedDateOfBirth!);
    }
  }

  @override
  void dispose() {
    firstNameCtrl.dispose();
    middleNameCtrl.dispose();
    surnameCtrl.dispose();
    dateOfBirthCtrl.dispose();
    nationalityCtrl.dispose();

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(userDetailsTransactionProvider);

    final notifier = ref.read(userDetailsTransactionProvider.notifier);

    final spacing = context.spacing;
    final radius = context.radius;
    final colorScheme = context.colorScheme;

    final now = DateTime.now();

    final maximumDate = DateTime(now.year - 18, now.month, now.day);

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
                  title: 'Basic Profile',
                  onClose: () {
                    context.pop();
                  },
                ),

                SizedBox(height: spacing.sm),

                Expanded(
                  child: SingleChildScrollView(
                    keyboardDismissBehavior:
                        ScrollViewKeyboardDismissBehavior.onDrag,
                    child: Column(
                      children: [
                        Container(
                          width: double.infinity,
                          padding: EdgeInsets.all(spacing.md),
                          decoration: BoxDecoration(
                            color: context.theme.cardColor,
                            borderRadius: BorderRadius.circular(
                              radius.edgeInsert,
                            ),
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
                                'Personal Information',
                                style: AppTextStyles.medium(
                                  context,
                                ).copyWith(fontWeight: FontWeight.w600),
                              ),

                              SizedBox(height: spacing.lg),

                              InputField(
                                controller: firstNameCtrl,
                                placeholder: 'First Name',
                                keyboardType: TextInputType.name,
                                onChanged: notifier.updateFirstName,
                              ),

                              SizedBox(height: spacing.sm),

                              InputField(
                                controller: middleNameCtrl,
                                placeholder: 'Middle Name',
                                keyboardType: TextInputType.name,
                                onChanged: notifier.updateMiddleName,
                              ),

                              SizedBox(height: spacing.sm),

                              InputField(
                                controller: surnameCtrl,
                                placeholder: 'Surname',
                                keyboardType: TextInputType.name,
                                onChanged: notifier.updateSurname,
                              ),

                              SizedBox(height: spacing.sm),

                              DateInputField(
                                controller: dateOfBirthCtrl,
                                placeholder: 'Date of Birth',
                                initialDate: selectedDateOfBirth ?? maximumDate,
                                firstDate: DateTime(1900),
                                lastDate: maximumDate,
                                onDateSelected: (date) {
                                  setState(() {
                                    selectedDateOfBirth = date;
                                  });

                                  notifier.updateDateOfBirth(date);
                                },
                              ),

                              SizedBox(height: spacing.sm),

                              AppSearchDropdownField<GenderType>(
                                selected: gender,
                                values: GenderType.values,
                                hint: 'Gender',
                                displayText: (value) {
                                  return value.displayName;
                                },
                                filter: (value, query) {
                                  return value.displayName
                                      .toLowerCase()
                                      .contains(query);
                                },
                                onSelect: (value) {
                                  setState(() {
                                    gender = value;
                                  });

                                  notifier.updateGender(value);
                                },
                                itemBuilder: (context, value) {
                                  return Padding(
                                    padding: EdgeInsets.symmetric(
                                      horizontal: spacing.padding,
                                      vertical: spacing.sm,
                                    ),
                                    child: Text(
                                      value.displayName,
                                      style: AppTextStyles.small(context),
                                    ),
                                  );
                                },
                              ),

                              SizedBox(height: spacing.sm),

                              InputField(
                                controller: nationalityCtrl,
                                placeholder: 'Nationality',
                                keyboardType: TextInputType.text,
                                onChanged: notifier.updateNationality,
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
                            ],
                          ),
                        ),

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
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _formatDate(DateTime date) {
    final year = date.year.toString();

    final month = date.month.toString().padLeft(2, '0');

    final day = date.day.toString().padLeft(2, '0');

    return '$year-$month-$day';
  }

  Future<void> _handleUpdate() async {
    FocusScope.of(context).unfocus();

    final state = ref.read(userDetailsTransactionProvider);

    if (!state.isValid) {
      await DialogService.error(
        context,
        message: 'Please complete all required fields',
      );

      return;
    }

    try {
      await ref
          .read(userDetailsTransactionProvider.notifier)
          .updateUserDetails();

      if (!mounted) {
        return;
      }

      /*
       * ProfileScreen owns userDetailsProvider now.
       * Refresh it so that the profile screen receives
       * the newly saved data when this screen closes.
       */
      ref.invalidate(userDetailsProvider);

      await DialogService.success(
        context,
        message: 'Basic profile updated successfully',
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
