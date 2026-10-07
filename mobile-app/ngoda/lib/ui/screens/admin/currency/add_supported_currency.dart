import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:ngoda/data_models/currency/currency.dart';
import 'package:ngoda/services/dialog_service.dart';
import 'package:ngoda/ui/extensions/app_size.dart';
import 'package:ngoda/ui/extensions/theme_extension.dart';
import 'package:ngoda/ui/screens/admin/provider/admin_dashboard_provider.dart';
import 'package:ngoda/ui/screens/admin/provider/admin_transactions_provider.dart';
import 'package:ngoda/ui/widgets/app_button.dart';
import 'package:ngoda/ui/widgets/app_toggle.dart';
import 'package:ngoda/ui/widgets/input_field.dart';
import 'package:ngoda/ui/widgets/view_header.dart';

class AddSupportedCurrencyScreen extends ConsumerStatefulWidget {
  final Currency? currency;

  const AddSupportedCurrencyScreen({super.key, this.currency});

  bool get isEditMode => currency != null;

  @override
  ConsumerState<AddSupportedCurrencyScreen> createState() =>
      _AddSupportedCurrencyScreenState();
}

class _AddSupportedCurrencyScreenState
    extends ConsumerState<AddSupportedCurrencyScreen> {
  final nameCtrl = TextEditingController();
  final codeCtrl = TextEditingController();
  final symbolCtrl = TextEditingController();
  final decimalsCtrl = TextEditingController();
  final rateUrlCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();

    final currency = widget.currency;

    if (currency != null) {
      nameCtrl.text = currency.name;
      codeCtrl.text = currency.code;
      symbolCtrl.text = currency.symbol;
      decimalsCtrl.text = currency.decimals.toString();
      rateUrlCtrl.text = currency.rateApi ?? '';
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }

      final notifier = ref.read(adminTransactionsProvider.notifier);

      if (currency == null) {
        notifier.reset();
        return;
      }

      notifier.updateName(currency.name);

      notifier.updateCurrencyCode(currency.code);

      notifier.updateSymbol(currency.symbol);

      notifier.updateDecimals(currency.decimals.toString());

      notifier.updateRateUrl(currency.rateApi ?? '');

      notifier.updateCurrencyIsActive(currency.isActive);
    });
  }

  @override
  void dispose() {
    nameCtrl.dispose();
    codeCtrl.dispose();
    symbolCtrl.dispose();
    decimalsCtrl.dispose();
    rateUrlCtrl.dispose();

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
                      ? 'Edit Supported Currency'
                      : 'Add Supported Currency',
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
                          color: colorScheme.surface,
                          borderRadius: BorderRadius.circular(
                            radius.cardRadius,
                          ),
                          border: Border.all(color: colorScheme.outlineVariant),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            InputField(
                              controller: nameCtrl,
                              placeholder: 'Currency Name',
                              keyboardType: TextInputType.text,
                              onChanged: notifier.updateName,
                            ),

                            SizedBox(height: spacing.sm),

                            InputField(
                              controller: codeCtrl,
                              placeholder: 'Currency Code',
                              keyboardType: TextInputType.text,
                              onChanged: notifier.updateCurrencyCode,
                            ),

                            SizedBox(height: spacing.sm),

                            InputField(
                              controller: symbolCtrl,
                              placeholder: 'Symbol',
                              keyboardType: TextInputType.text,
                              onChanged: notifier.updateSymbol,
                            ),

                            SizedBox(height: spacing.sm),

                            InputField(
                              controller: decimalsCtrl,
                              placeholder: 'Decimals',
                              keyboardType: TextInputType.number,
                              onChanged: notifier.updateDecimals,
                            ),

                            SizedBox(height: spacing.sm),

                            InputField(
                              controller: rateUrlCtrl,
                              placeholder: 'Rate URL',
                              keyboardType: TextInputType.url,
                              onChanged: notifier.updateRateUrl,
                            ),

                            SizedBox(height: spacing.sm),

                            AppToggle(
                              label: 'Is Active',
                              value: state.isActive,
                              onChanged: notifier.updateCurrencyIsActive,
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
                                  ? 'Update Currency'
                                  : 'Add Currency',
                              isProcessing: state.isLoading,
                              onPressed: !state.isValid || state.isLoading
                                  ? null
                                  : () async {
                                      await _handleSaveCurrency();
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

  Future<void> _handleSaveCurrency() async {
    try {
      FocusScope.of(context).unfocus();

      final state = ref.read(adminTransactionsProvider);

      final confirmed = await _confirmSaveCurrency(state.name!, state.code!);

      if (confirmed != true || !mounted) {
        return;
      }

      final notifier = ref.read(adminTransactionsProvider.notifier);

      await notifier.updateSupportedCurrencies(
        currencyCode: state.code!,
        decimals: state.decimals!,
        rateUrl: state.rateUrl!,
        symbol: state.symbol!,
        name: state.name!,
        isActive: state.isActive,
      );

      ref.invalidate(adminDashboardProvider);

      if (!mounted) {
        return;
      }

      await DialogService.success(
        context,
        message: widget.isEditMode
            ? 'Supported currency updated successfully'
            : 'Supported currency added successfully',
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

  Future<bool?> _confirmSaveCurrency(String name, String code) {
    return DialogService.confirm(
      context,
      title: widget.isEditMode
          ? 'Confirm Currency Update'
          : 'Confirm Supported Currency',
      message: widget.isEditMode
          ? 'Update currency $name\ncode $code'
          : 'Add currency $name\ncode $code',
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
    nameCtrl.clear();
    codeCtrl.clear();
    symbolCtrl.clear();
    decimalsCtrl.clear();
    rateUrlCtrl.clear();

    notifier.reset();
  }
}
