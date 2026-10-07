import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:ngoda/data_models/admin/operational_country.dart';
import 'package:ngoda/services/dialog_service.dart';
import 'package:ngoda/ui/extensions/app_size.dart';
import 'package:ngoda/ui/extensions/theme_extension.dart';
import 'package:ngoda/ui/screens/admin/provider/admin_dashboard_provider.dart';
import 'package:ngoda/ui/screens/admin/provider/admin_transactions_provider.dart';
import 'package:ngoda/ui/widgets/app_button.dart';
import 'package:ngoda/ui/widgets/app_toggle.dart';
import 'package:ngoda/ui/widgets/input_field.dart';
import 'package:ngoda/ui/widgets/view_header.dart';

class AddCountryScreen extends ConsumerStatefulWidget {
  final OperationalCountry? country;

  const AddCountryScreen({super.key, this.country});

  bool get isEditMode => country != null;

  @override
  ConsumerState<AddCountryScreen> createState() => _AddCountryScreenState();
}

class _AddCountryScreenState extends ConsumerState<AddCountryScreen> {
  final countryCtrl = TextEditingController();
  final codeCtrl = TextEditingController();
  final callingCodeCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();

    final country = widget.country;

    if (country != null) {
      countryCtrl.text = country.name;
      codeCtrl.text = country.countryCode;
      callingCodeCtrl.text = country.callingCode;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }

      final notifier = ref.read(adminTransactionsProvider.notifier);

      if (country == null) {
        notifier.reset();
        return;
      }

      notifier.updateCountry(country.name);

      notifier.updateCode(country.countryCode);

      notifier.updateCallingCode(country.callingCode);

      notifier.updateIsActive(country.isActive);
    });
  }

  @override
  void dispose() {
    countryCtrl.dispose();
    codeCtrl.dispose();
    callingCodeCtrl.dispose();

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    final radius = context.radius;
    final colorScheme = context.colorScheme;

    final state = ref.watch(adminTransactionsProvider);

    final notifier = ref.read(adminTransactionsProvider.notifier);

    final isEditMode = widget.isEditMode;

    return Scaffold(
      body: SafeArea(
        child: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTap: () {
            FocusScope.of(context).unfocus();
          },
          child: Column(
            children: [
              Padding(
                padding: EdgeInsets.fromLTRB(
                  spacing.md,
                  spacing.sm,
                  spacing.md,
                  0,
                ),
                child: ViewHeader(
                  title: isEditMode
                      ? 'Edit Operational Country'
                      : 'Add Operational Country',
                  onClose: () {
                    _closeScreen(notifier);
                  },
                ),
              ),

              Expanded(
                child: SingleChildScrollView(
                  padding: EdgeInsets.fromLTRB(
                    spacing.md,
                    spacing.md,
                    spacing.md,
                    spacing.lg,
                  ),
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
                            radius.cardRadius,
                          ),
                          border: Border.all(color: colorScheme.outlineVariant),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            InputField(
                              controller: countryCtrl,
                              placeholder: 'Country',
                              keyboardType: TextInputType.text,
                              onChanged: notifier.updateCountry,
                            ),

                            SizedBox(height: spacing.md),

                            InputField(
                              controller: codeCtrl,
                              placeholder: 'Country Code',
                              keyboardType: TextInputType.text,
                              onChanged: notifier.updateCode,
                            ),

                            SizedBox(height: spacing.md),

                            InputField(
                              controller: callingCodeCtrl,
                              placeholder: 'Country Calling Code',
                              keyboardType: TextInputType.phone,
                              onChanged: notifier.updateCallingCode,
                            ),

                            SizedBox(height: spacing.md),

                            AppToggle(
                              label: 'Is Active',
                              value: state.isActive,
                              onChanged: notifier.updateIsActive,
                            ),
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
                                _closeScreen(notifier);
                              },
                            ),
                          ),

                          SizedBox(width: spacing.sm),

                          Expanded(
                            child: AppButton(
                              text: isEditMode
                                  ? 'Update Country'
                                  : 'Add Country',
                              isProcessing: state.isLoading,
                              onPressed: !state.isValid || state.isLoading
                                  ? null
                                  : () async {
                                      await _handleSaveCountry(
                                        state.country!,
                                        state.code!,
                                      );
                                    },
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
    );
  }

  Future<void> _handleSaveCountry(String country, String code) async {
    try {
      FocusScope.of(context).unfocus();

      final confirmed = await _confirmSave(country, code);

      if (confirmed != true || !mounted) {
        return;
      }

      final notifier = ref.read(adminTransactionsProvider.notifier);

      await notifier.updateOperationalCountry();

      ref.invalidate(adminDashboardProvider);

      if (!mounted) {
        return;
      }

      await DialogService.success(
        context,
        message: widget.isEditMode
            ? 'Operational country updated successfully'
            : 'Operational country added successfully',
      );

      if (!mounted) {
        return;
      }

      _resetForm(notifier);

      context.pop();
    } catch (e) {
      if (!mounted) {
        return;
      }

      await DialogService.error(context, message: e.toString());
    }
  }

  Future<bool?> _confirmSave(String country, String code) {
    return DialogService.confirm(
      context,
      title: widget.isEditMode
          ? 'Confirm Country Update'
          : 'Confirm Operational Country',
      message: widget.isEditMode
          ? 'Update country $country\ncode $code'
          : 'Add country $country\ncode $code',
    );
  }

  void _closeScreen(dynamic notifier) {
    if (!mounted) {
      return;
    }

    _resetForm(notifier);

    context.pop();
  }

  void _resetForm(dynamic notifier) {
    countryCtrl.clear();
    codeCtrl.clear();
    callingCodeCtrl.clear();

    notifier.reset();
  }
}
