import 'package:flutter/material.dart';
import 'package:ngoda/ui/extensions/app_size.dart';
import 'package:ngoda/ui/shared/app_text_styles.dart';

class AppValueRow extends StatelessWidget {
  final String label;
  final String value;

  final String? secondaryValue;

  final TextStyle? labelStyle;
  final TextStyle? valueStyle;
  final TextStyle? secondaryValueStyle;

  final Color? valueColor;
  final Color? secondaryValueColor;

  final bool addBottomSpacing;

  const AppValueRow({
    super.key,
    required this.label,
    required this.value,
    this.secondaryValue,
    this.labelStyle,
    this.valueStyle,
    this.secondaryValueStyle,
    this.valueColor,
    this.secondaryValueColor,
    this.addBottomSpacing = true,
  });

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;

    final resolvedValueStyle = valueStyle ?? AppTextStyles.smallNumber(context);

    final resolvedSecondaryValueStyle =
        secondaryValueStyle ?? AppTextStyles.tinyNumber(context);

    return Padding(
      padding: EdgeInsets.only(bottom: addBottomSpacing ? spacing.sm : 0),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: labelStyle ?? AppTextStyles.small(context),
                ),
              ),
              SizedBox(width: spacing.sm),
              Text(
                value,
                textAlign: TextAlign.right,
                style: valueColor == null
                    ? resolvedValueStyle
                    : resolvedValueStyle.copyWith(color: valueColor),
              ),
            ],
          ),

          if (secondaryValue != null) ...[
            SizedBox(height: spacing.xs),
            Align(
              alignment: Alignment.centerRight,
              child: Text(
                secondaryValue!,
                textAlign: TextAlign.right,
                style: secondaryValueColor == null
                    ? resolvedSecondaryValueStyle
                    : resolvedSecondaryValueStyle.copyWith(
                        color: secondaryValueColor,
                      ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// import 'package:flutter/material.dart';
// import 'package:ngoda/ui/extensions/app_size.dart';
// import 'package:ngoda/ui/shared/app_text_styles.dart';

// class AppValueRow extends StatelessWidget {
//   final String label;
//   final String value;

//   final String? secondaryValue;

//   final TextStyle? labelStyle;
//   final TextStyle? valueStyle;
//   final TextStyle? secondaryValueStyle;

//   final bool addBottomSpacing;

//   const AppValueRow({
//     super.key,
//     required this.label,
//     required this.value,
//     this.secondaryValue,
//     this.labelStyle,
//     this.valueStyle,
//     this.secondaryValueStyle,
//     this.addBottomSpacing = true,
//   });

//   @override
//   Widget build(BuildContext context) {
//     final spacing = context.spacing;

//     return Padding(
//       padding: EdgeInsets.only(bottom: addBottomSpacing ? spacing.sm : 0),
//       child: Column(
//         children: [
//           Row(
//             children: [
//               Expanded(
//                 child: Text(
//                   label,
//                   style: labelStyle ?? AppTextStyles.small(context),
//                 ),
//               ),
//               SizedBox(width: spacing.sm),
//               Text(
//                 value,
//                 textAlign: TextAlign.right,
//                 style: valueStyle ?? AppTextStyles.smallNumber(context),
//               ),
//             ],
//           ),

//           if (secondaryValue != null) ...[
//             SizedBox(height: spacing.xs),
//             Align(
//               alignment: Alignment.centerRight,
//               child: Text(
//                 secondaryValue!,
//                 textAlign: TextAlign.right,
//                 style: secondaryValueStyle ?? AppTextStyles.tinyNumber(context),
//               ),
//             ),
//           ],
//         ],
//       ),
//     );
//   }
// }
