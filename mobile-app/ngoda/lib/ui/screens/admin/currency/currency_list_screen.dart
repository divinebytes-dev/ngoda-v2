import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:ngoda/data_models/currency/currency.dart';
import 'package:ngoda/ui/extensions/app_size.dart';
import 'package:ngoda/ui/extensions/theme_extension.dart';
import 'package:ngoda/ui/screens/admin/provider/admin_dashboard_provider.dart';
import 'package:ngoda/ui/shared/app_text_styles.dart';
import 'package:ngoda/ui/widgets/app_error_state.dart';
import 'package:ngoda/ui/widgets/app_loader.dart';
import 'package:ngoda/ui/widgets/view_header.dart';

class CurrencyListScreen extends ConsumerWidget {
  const CurrencyListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dashboardAsync = ref.watch(adminDashboardProvider);

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            ViewHeader(
              title: 'Supported Currency List',
              onClose: () {
                context.pop();
              },
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
                      message: 'Failed to load supported currencies',
                      buttonText: 'Retry',
                      onAction: () {
                        ref.invalidate(adminDashboardProvider);
                      },
                    );
                  }

                  final currencies = dashboard.supportedCurrencies;

                  if (currencies.isEmpty) {
                    return _EmptyCurrencyState();
                  }

                  return _CurrencyList(currencies: currencies);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CurrencyList extends StatelessWidget {
  final List<Currency> currencies;

  const _CurrencyList({required this.currencies});

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;

    return ListView.separated(
      padding: EdgeInsets.fromLTRB(
        spacing.md,
        spacing.md,
        spacing.md,
        spacing.lg,
      ),
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      itemCount: currencies.length,
      separatorBuilder: (context, index) {
        return SizedBox(height: spacing.sm);
      },
      itemBuilder: (context, index) {
        return _CurrencyDetails(currency: currencies[index]);
      },
    );
  }
}

class _CurrencyDetails extends StatelessWidget {
  final Currency currency;

  const _CurrencyDetails({required this.currency});

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    final radius = context.radius;
    final iconSize = context.iconSize;
    final colorScheme = context.colorScheme;

    return Material(
      color: colorScheme.surface,
      borderRadius: BorderRadius.circular(radius.cardRadius),
      child: InkWell(
        borderRadius: BorderRadius.circular(radius.cardRadius),
        onTap: () {
          context.push('/currency/add-supported-currency', extra: currency);
        },
        child: Container(
          width: double.infinity,
          padding: EdgeInsets.all(spacing.md),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(radius.cardRadius),
            border: Border.all(color: colorScheme.outlineVariant),
          ),
          child: Row(
            children: [
              Container(
                padding: EdgeInsets.symmetric(
                  horizontal: spacing.md,
                  vertical: spacing.sm,
                ),
                decoration: BoxDecoration(
                  color: colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(radius.md),
                ),
                child: Text(
                  currency.code.toUpperCase(),
                  style: AppTextStyles.small(context).copyWith(
                    color: colorScheme.onPrimaryContainer,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),

              SizedBox(width: spacing.md),

              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      currency.name,
                      style: AppTextStyles.small(
                        context,
                      ).copyWith(fontWeight: FontWeight.w600),
                    ),

                    SizedBox(height: spacing.xs),

                    Text(
                      currency.symbol,
                      style: AppTextStyles.tiny(
                        context,
                      ).copyWith(color: colorScheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),

              Icon(
                Icons.chevron_right_rounded,
                size: iconSize.large,
                color: colorScheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyCurrencyState extends StatelessWidget {
  const _EmptyCurrencyState();

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    final iconSize = context.iconSize;
    final colorScheme = context.colorScheme;

    return Center(
      child: Padding(
        padding: EdgeInsets.all(spacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.currency_exchange_rounded,
              size: iconSize.xl,
              color: colorScheme.onSurfaceVariant,
            ),

            SizedBox(height: spacing.md),

            Text(
              'No supported currencies found',
              textAlign: TextAlign.center,
              style: AppTextStyles.small(
                context,
              ).copyWith(color: colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}
