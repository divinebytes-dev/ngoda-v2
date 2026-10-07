import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:ngoda/data_models/kyc/user_kyc_details.dart';

import 'package:ngoda/services/dialog_service.dart';
import 'package:ngoda/ui/enums/enums.dart';
import 'package:ngoda/ui/extensions/app_size.dart';
import 'package:ngoda/ui/extensions/theme_extension.dart';
import 'package:ngoda/ui/screens/customer/details/providers/user_details_provider.dart';
import 'package:ngoda/ui/screens/customer/details/providers/user_kyc_details_provider.dart';
import 'package:ngoda/ui/shared/app_text_styles.dart';
import 'package:ngoda/ui/widgets/app_button.dart';
import 'package:ngoda/ui/widgets/app_search_dropdown_field.dart';
import 'package:ngoda/ui/widgets/date_time_input.dart';
import 'package:ngoda/ui/widgets/input_field.dart';
import 'package:ngoda/ui/widgets/view_header.dart';

class KycDetailsScreen extends ConsumerStatefulWidget {
  final UserKycDetails? kycDetails;

  const KycDetailsScreen({super.key, this.kycDetails});

  @override
  ConsumerState<KycDetailsScreen> createState() => _KycDetailsScreenState();
}

class _KycDetailsScreenState extends ConsumerState<KycDetailsScreen> {
  final idNumberCtrl = TextEditingController();
  final idExpiryCtrl = TextEditingController();
  final occupationCtrl = TextEditingController();
  final taxNumberCtrl = TextEditingController();

  IdentificationType? identificationType;
  SourceOfFundsType? sourceOfFunds;

  DateTime? selectedExpiryDate;

  KycStatus kycStatus = KycStatus.notStarted;

  @override
  void initState() {
    super.initState();

    _initialiseKycDetails();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }

      ref.read(userKycDetailsProvider.notifier).initKyc(widget.kycDetails);
    });
  }

  void _initialiseKycDetails() {
    final kyc = widget.kycDetails;

    if (kyc == null) {
      return;
    }

    idNumberCtrl.text = kyc.idNumber ?? '';
    occupationCtrl.text = kyc.occupation ?? '';
    taxNumberCtrl.text = kyc.taxNumber ?? '';

    identificationType = _parseIdentificationType(kyc.idType);

    sourceOfFunds = _parseSourceOfFunds(kyc.sourceOfFunds);

    kycStatus = _parseKycStatus(kyc.status);

    selectedExpiryDate = _parseDate(kyc.expiryDate);

    if (selectedExpiryDate != null) {
      idExpiryCtrl.text = _formatDate(selectedExpiryDate!);
    }
  }

  IdentificationType? _parseIdentificationType(dynamic value) {
    if (value == null) {
      return null;
    }

    if (value is IdentificationType) {
      return value;
    }

    if (value is String) {
      return IdentificationType.fromJson(value);
    }

    return null;
  }

  SourceOfFundsType? _parseSourceOfFunds(dynamic value) {
    if (value == null) {
      return null;
    }

    if (value is SourceOfFundsType) {
      return value;
    }

    if (value is String) {
      return SourceOfFundsType.fromJson(value);
    }

    return null;
  }

  KycStatus _parseKycStatus(dynamic value) {
    if (value == null) {
      return KycStatus.notStarted;
    }

    if (value is KycStatus) {
      return value;
    }

    if (value is String) {
      return KycStatus.fromJson(value);
    }

    return KycStatus.notStarted;
  }

  DateTime? _parseDate(dynamic value) {
    if (value == null) {
      return null;
    }

    if (value is DateTime) {
      return value;
    }

    if (value is String) {
      return DateTime.tryParse(value);
    }

    return null;
  }

  @override
  void dispose() {
    idNumberCtrl.dispose();
    idExpiryCtrl.dispose();
    occupationCtrl.dispose();
    taxNumberCtrl.dispose();

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(userKycDetailsProvider);

    final notifier = ref.read(userKycDetailsProvider.notifier);

    final spacing = context.spacing;
    final radius = context.radius;
    final colorScheme = context.colorScheme;

    final now = DateTime.now();

    final minimumExpiryDate = DateTime(now.year, now.month, now.day);

    final initialExpiryDate =
        selectedExpiryDate != null &&
            !selectedExpiryDate!.isBefore(minimumExpiryDate)
        ? selectedExpiryDate!
        : DateTime(now.year + 1, now.month, now.day);

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
                  title: 'KYC Details',
                  onClose: () {
                    context.pop();
                  },
                ),

                SizedBox(height: spacing.md),

                _KycStatusCard(status: kycStatus),

                SizedBox(height: spacing.lg),

                Expanded(
                  child: SingleChildScrollView(
                    keyboardDismissBehavior:
                        ScrollViewKeyboardDismissBehavior.onDrag,
                    child: Container(
                      width: double.infinity,
                      padding: EdgeInsets.all(spacing.sm),
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
                            'Identity Details',
                            style: AppTextStyles.medium(
                              context,
                            ).copyWith(fontWeight: FontWeight.w600),
                          ),

                          SizedBox(height: spacing.lg),

                          AppSearchDropdownField<IdentificationType>(
                            selected: identificationType,
                            values: IdentificationType.values,
                            hint: 'Identification Type',
                            displayText: (value) {
                              return value.displayName;
                            },
                            filter: (value, query) {
                              return value.displayName.toLowerCase().contains(
                                query,
                              );
                            },
                            onSelect: (value) {
                              setState(() {
                                identificationType = value;
                              });

                              notifier.updateIdentificationType(value);
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
                            controller: idNumberCtrl,
                            placeholder: _idNumberLabel,
                            keyboardType: TextInputType.text,
                            onChanged: notifier.updateIdNumber,
                          ),

                          SizedBox(height: spacing.sm),

                          DateInputField(
                            controller: idExpiryCtrl,
                            placeholder: 'Expiry Date',
                            initialDate: initialExpiryDate,
                            firstDate: minimumExpiryDate,
                            lastDate: DateTime(now.year + 30, 12, 31),
                            onDateSelected: (date) {
                              setState(() {
                                selectedExpiryDate = date;
                              });

                              notifier.updateExpiryDate(date);
                            },
                          ),

                          SizedBox(height: spacing.xl),

                          Text(
                            'Financial Information',
                            style: AppTextStyles.medium(
                              context,
                            ).copyWith(fontWeight: FontWeight.w600),
                          ),

                          SizedBox(height: spacing.lg),

                          InputField(
                            controller: occupationCtrl,
                            placeholder: 'Occupation',
                            keyboardType: TextInputType.text,
                            onChanged: notifier.updateOccupation,
                          ),

                          SizedBox(height: spacing.sm),

                          AppSearchDropdownField<SourceOfFundsType>(
                            selected: sourceOfFunds,
                            values: SourceOfFundsType.values,
                            hint: 'Source of Funds',
                            displayText: (value) {
                              return value.displayName;
                            },
                            filter: (value, query) {
                              return value.displayName.toLowerCase().contains(
                                query,
                              );
                            },
                            onSelect: (value) {
                              setState(() {
                                sourceOfFunds = value;
                              });

                              notifier.updateSourceOfFunds(value);
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
                            controller: taxNumberCtrl,
                            placeholder: 'Tax Number (Optional)',
                            keyboardType: TextInputType.text,
                            onChanged: notifier.updateTaxNumber,
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

  String get _idNumberLabel {
    switch (identificationType) {
      case IdentificationType.nationalId:
        return 'National ID Number';

      case IdentificationType.passport:
        return 'Passport Number';

      case IdentificationType.driversLicense:
        return "Driver's Licence Number";

      case IdentificationType.unknown:
      case null:
        return 'ID / Passport Number';
    }
  }

  String _formatDate(DateTime date) {
    final year = date.year.toString();

    final month = date.month.toString().padLeft(2, '0');

    final day = date.day.toString().padLeft(2, '0');

    return '$year-$month-$day';
  }

  Future<void> _handleUpdate() async {
    FocusScope.of(context).unfocus();

    final state = ref.read(userKycDetailsProvider);

    if (!state.isValid) {
      return;
    }

    try {
      await ref.read(userKycDetailsProvider.notifier).updateUserKyc();

      if (!mounted) {
        return;
      }

      ref.invalidate(userDetailsProvider);

      await DialogService.success(
        context,
        message: 'KYC details updated successfully',
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

class _KycStatusCard extends StatelessWidget {
  final KycStatus status;

  const _KycStatusCard({required this.status});

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    final radius = context.radius;
    final iconSize = context.iconSize;
    final colorScheme = context.colorScheme;

    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(spacing.md),
      decoration: BoxDecoration(
        color: context.theme.cardColor,
        borderRadius: BorderRadius.circular(radius.cardRadius),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.09),
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: EdgeInsets.all(spacing.sm),
            decoration: BoxDecoration(
              color: colorScheme.primary.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(radius.cardRadius),
            ),
            child: Icon(
              _statusIcon,
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
                  'KYC Status',
                  style: AppTextStyles.small(
                    context,
                  ).copyWith(color: colorScheme.onSurfaceVariant),
                ),

                SizedBox(height: spacing.xs),

                Text(
                  status.displayName,
                  style: AppTextStyles.medium(
                    context,
                  ).copyWith(fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  IconData get _statusIcon {
    switch (status) {
      case KycStatus.notStarted:
        return Icons.info_outline;

      case KycStatus.pending:
        return Icons.schedule_outlined;

      case KycStatus.underReview:
        return Icons.manage_search_outlined;

      case KycStatus.verified:
        return Icons.verified_outlined;

      case KycStatus.rejected:
        return Icons.cancel_outlined;

      case KycStatus.expired:
        return Icons.event_busy_outlined;

      case KycStatus.unknown:
        return Icons.help_outline_rounded;
    }
  }
}
