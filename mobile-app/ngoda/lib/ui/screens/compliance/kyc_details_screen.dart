import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:ngoda/data_models/kyc/user_kyc_details.dart';
import 'package:ngoda/ui/extensions/app_size.dart';
import 'package:ngoda/ui/widgets/view_header.dart';

class KycDetailsScreen extends StatelessWidget {
  final UserKycDetails details;

  const KycDetailsScreen({super.key, required this.details});

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing.md;

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            ViewHeader(
              title: "KYC Details",
              onClose: () {
                context.pop();
              },
            ),

            Expanded(
              child: SingleChildScrollView(
                padding: EdgeInsets.all(spacing),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _SectionCard(
                      title: "Identification",
                      icon: Icons.badge_outlined,
                      children: [
                        _DetailRow(
                          label: "ID Type",
                          value: _displayValue(details.idType),
                        ),
                        _DetailRow(
                          label: "ID Number",
                          value: _displayValue(details.idNumber),
                        ),
                        _DetailRow(
                          label: "Expiry Date",
                          value: _formatDate(details.expiryDate),
                          isLast: true,
                        ),
                      ],
                    ),

                    SizedBox(height: spacing),

                    _SectionCard(
                      title: "Financial Information",
                      icon: Icons.account_balance_wallet_outlined,
                      children: [
                        _DetailRow(
                          label: "Occupation",
                          value: _displayValue(details.occupation),
                        ),
                        _DetailRow(
                          label: "Source of Funds",
                          value: _displayValue(details.sourceOfFunds),
                        ),
                        _DetailRow(
                          label: "Tax Number",
                          value: _displayValue(details.taxNumber),
                          isLast: true,
                        ),
                      ],
                    ),

                    SizedBox(height: spacing),

                    _SectionCard(
                      title: "KYC Information",
                      icon: Icons.verified_user_outlined,
                      children: [
                        _DetailRow(
                          label: "Status",
                          value: _formatStatus(details.status.toString()),
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
    );
  }

  static String _displayValue(String? value) {
    if (value == null || value.trim().isEmpty) {
      return "Not provided";
    }

    return value;
  }

  static String _formatDate(DateTime? date) {
    if (date == null) {
      return "Not available";
    }

    final day = date.day.toString().padLeft(2, '0');

    final month = date.month.toString().padLeft(2, '0');

    return "$day/$month/${date.year}";
  }

  static String _formatStatus(String value) {
    var status = value;

    if (status.contains('.')) {
      status = status.split('.').last;
    }

    status = status.replaceAllMapped(
      RegExp(r'([a-z])([A-Z])'),
      (match) =>
          '${match.group(1)} '
          '${match.group(2)}',
    );

    status = status.replaceAll('_', ' ');

    if (status.trim().isEmpty) {
      return "Not available";
    }

    return status
        .split(' ')
        .where((value) => value.isNotEmpty)
        .map(
          (value) =>
              '${value[0].toUpperCase()}'
              '${value.substring(1).toLowerCase()}',
        )
        .join(' ');
  }
}

class _SectionCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final List<Widget> children;

  const _SectionCard({
    required this.title,
    required this.icon,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(context.spacing.md),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(context.spacing.md),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: Theme.of(
                    context,
                  ).colorScheme.primary.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(context.spacing.sm),
                ),
                child: Icon(icon, color: Theme.of(context).colorScheme.primary),
              ),

              SizedBox(width: context.spacing.md),

              Expanded(
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
            ],
          ),

          SizedBox(height: context.spacing.md),

          ...children,
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;
  final bool isLast;

  const _DetailRow({
    required this.label,
    required this.value,
    this.isLast = false,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: EdgeInsets.symmetric(vertical: context.spacing.sm),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 2,
                child: Text(
                  label,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ),

              SizedBox(width: context.spacing.md),

              Expanded(
                flex: 3,
                child: Text(
                  value,
                  textAlign: TextAlign.right,
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
        ),

        if (!isLast) const Divider(height: 1),
      ],
    );
  }
}
