import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:ngoda/services/dialog_service.dart';
import 'package:ngoda/ui/extensions/app_size.dart';
import 'package:ngoda/ui/extensions/theme_extension.dart';
import 'package:ngoda/ui/screens/admin/provider/admin_dashboard_provider.dart';
import 'package:ngoda/ui/screens/admin/provider/admin_transactions_provider.dart';
import 'package:ngoda/ui/widgets/app_button.dart';
import 'package:ngoda/ui/widgets/app_error_state.dart';
import 'package:ngoda/ui/widgets/app_loader.dart';
import 'package:ngoda/ui/widgets/app_search_dropdown_field.dart';
import 'package:ngoda/ui/widgets/app_toggle.dart';
import 'package:ngoda/ui/widgets/view_header.dart';

class AddCountryCurrencyScreen extends ConsumerStatefulWidget {
  const AddCountryCurrencyScreen({super.key});

  @override
  ConsumerState<AddCountryCurrencyScreen> createState() =>
      _AddCountryCurrencyScreenState();
}

class _AddCountryCurrencyScreenState
    extends ConsumerState<AddCountryCurrencyScreen> {
  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }

      ref.read(adminTransactionsProvider.notifier).reset();
    });
  }

  @override
  Widget build(BuildContext context) {
    final dashboardAsync = ref.watch(adminDashboardProvider);

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(
                context.spacing.md,
                context.spacing.sm,
                context.spacing.md,
                0,
              ),
              child: ViewHeader(
                title: 'Add Supported Country Currency',
                onClose: _closeScreen,
              ),
            ),

            Expanded(
              child: dashboardAsync.when(
                loading: () => const AppLoader(),

                error: (error, stackTrace) {
                  return AppErrorState(
                    message: error.toString(),
                    buttonText: 'Retry',
                    onAction: () {
                      ref.invalidate(adminDashboardProvider);
                    },
                  );
                },

                data: (response) {
                  if (response.error != null) {
                    return AppErrorState(
                      message: response.error!,
                      buttonText: 'Retry',
                      onAction: () {
                        ref.invalidate(adminDashboardProvider);
                      },
                    );
                  }

                  final dashboard = response.result;

                  if (dashboard == null) {
                    return AppErrorState(
                      message: 'Missing required country and currency data',
                      buttonText: 'Retry',
                      onAction: () {
                        ref.invalidate(adminDashboardProvider);
                      },
                    );
                  }

                  final countries = dashboard.operationalCountries;

                  final currencies = dashboard.supportedCurrencies;

                  if (countries.isEmpty) {
                    return AppErrorState(
                      message: 'No operational countries available',
                      onAction: () {
                        context.pop();
                      },
                    );
                  }

                  if (currencies.isEmpty) {
                    return AppErrorState(
                      message: 'No supported currencies available',
                      onAction: () {
                        context.pop();
                      },
                    );
                  }

                  return _buildForm(countries, currencies);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildForm(List<dynamic> countries, List<dynamic> currencies) {
    final spacing = context.spacing;
    final radius = context.radius;
    final colorScheme = context.colorScheme;

    final state = ref.watch(adminTransactionsProvider);

    final notifier = ref.read(adminTransactionsProvider.notifier);

    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: () {
        FocusScope.of(context).unfocus();
      },
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          spacing.md,
          spacing.md,
          spacing.md,
          spacing.lg,
        ),
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        child: Container(
          width: double.infinity,
          padding: EdgeInsets.all(spacing.md),
          decoration: BoxDecoration(
            color: colorScheme.surface,
            borderRadius: BorderRadius.circular(radius.cardRadius),
            border: Border.all(color: colorScheme.outlineVariant),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AppSearchDropdownField(
                selected: state.operationalCountry,
                values: countries,
                hint: 'Search Operational Country',
                displayText: (country) {
                  return country.name;
                },
                filter: (country, query) {
                  return country.name.toLowerCase().contains(query) ||
                      country.countryCode.toLowerCase().contains(query);
                },
                onSelect: (country) {
                  notifier.updateOpCountry(country);
                },
              ),

              SizedBox(height: spacing.md),

              AppSearchDropdownField(
                selected: state.currency,
                values: currencies,
                hint: 'Search Supported Currency',
                displayText: (currency) {
                  return '${currency.code.toUpperCase()} - ${currency.name}';
                },
                filter: (currency, query) {
                  return currency.code.toLowerCase().contains(query) ||
                      currency.name.toLowerCase().contains(query) ||
                      currency.symbol.toLowerCase().contains(query);
                },
                onSelect: (currency) {
                  notifier.updateCurrency(currency);
                },
              ),

              SizedBox(height: spacing.md),

              AppToggle(
                label: 'Is Active',
                value: state.isActive,
                onChanged: notifier.updateIsActive,
              ),

              SizedBox(height: spacing.lg),

              Row(
                children: [
                  Expanded(
                    child: AppButton(
                      text: 'Cancel',
                      isPrimary: false,
                      isDisabled: state.isLoading,
                      onPressed: _closeScreen,
                    ),
                  ),

                  SizedBox(width: spacing.sm),

                  Expanded(
                    child: AppButton(
                      text: 'Add Currency',
                      isProcessing: state.isLoading,
                      onPressed: !state.isValid || state.isLoading
                          ? null
                          : () async {
                              await _handleUpdateCountry(
                                state.operationalCountry!.countryCode,
                                state.currency!.code,
                                state.isActive,
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
    );
  }

  Future<void> _handleUpdateCountry(
    String countryCode,
    String currencyCode,
    bool isActive,
  ) async {
    try {
      FocusScope.of(context).unfocus();

      final confirmed = await _confirmUpdate(countryCode, currencyCode);

      if (confirmed != true || !mounted) {
        return;
      }

      final notifier = ref.read(adminTransactionsProvider.notifier);

      await notifier.updateCountryCurrencies(
        currencyCode: currencyCode,
        countryCode: countryCode,
        isActive: isActive,
      );

      ref.invalidate(adminDashboardProvider);

      if (!mounted) {
        return;
      }

      await DialogService.success(
        context,
        message: 'Country currency updated successfully',
      );

      if (!mounted) {
        return;
      }

      notifier.reset();
    } catch (e) {
      if (!mounted) {
        return;
      }

      await DialogService.error(context, message: e.toString());
    }
  }

  Future<bool?> _confirmUpdate(String countryCode, String currencyCode) {
    return DialogService.confirm(
      context,
      title: 'Confirm Country Currency',
      message:
          'Add currency $currencyCode\n'
          'to country $countryCode',
    );
  }

  void _closeScreen() {
    if (!mounted) {
      return;
    }

    ref.read(adminTransactionsProvider.notifier).reset();

    context.pop();
  }
}
