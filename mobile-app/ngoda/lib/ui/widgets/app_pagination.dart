import 'package:flutter/material.dart';

import 'package:ngoda/ui/extensions/app_size.dart';
import 'package:ngoda/ui/extensions/theme_extension.dart';
import 'package:ngoda/ui/shared/app_text_styles.dart';

class AppPagination extends StatelessWidget {
  const AppPagination({
    super.key,
    required this.page,
    required this.totalPages,
    required this.totalEntries,
    required this.hasPrevious,
    required this.hasNext,
    required this.onPrevious,
    required this.onNext,
    this.isLoading = false,
    this.entryLabel = 'items',
    this.pageSize,
    this.pageSizeOptions = const [10, 25, 50, 100],
    this.onPageSizeChanged,
  });

  final int page;
  final int totalPages;
  final int totalEntries;

  final bool hasPrevious;
  final bool hasNext;
  final bool isLoading;

  final VoidCallback onPrevious;
  final VoidCallback onNext;

  final String entryLabel;

  final int? pageSize;
  final List<int> pageSizeOptions;
  final ValueChanged<int>? onPageSizeChanged;

  bool get _showPageSize => pageSize != null && onPageSizeChanged != null;

  @override
  Widget build(BuildContext context) {
    if (totalEntries == 0) {
      return const SizedBox.shrink();
    }

    final spacing = context.spacing;
    final colorScheme = context.colorScheme;

    final safeTotalPages = totalPages > 0 ? totalPages : 1;
    final safePage = page.clamp(1, safeTotalPages);

    final hasValidPageSize = pageSize != null && pageSize! > 0;

    final startEntry = hasValidPageSize
        ? ((safePage - 1) * pageSize!) + 1
        : null;

    final endEntry = hasValidPageSize
        ? (safePage * pageSize!).clamp(0, totalEntries)
        : null;

    return Container(
      width: double.infinity,
      margin: EdgeInsets.fromLTRB(
        spacing.sm,
        spacing.sm,
        spacing.md,
        spacing.sm,
      ),
      padding: EdgeInsets.all(spacing.sm),
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        borderRadius: BorderRadius.circular(context.radius.cardRadius),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.1),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ---------------------------------------------------------
          // TRANSACTION RANGE + PAGE SIZE DROPDOWN
          // ---------------------------------------------------------

          Row(
            children: [
              Expanded(
                child: Text(
                  hasValidPageSize
                      ? 'Showing $startEntry–$endEntry of $totalEntries'
                      : '$totalEntries $entryLabel',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.tiny(
                    context,
                  ).copyWith(color: colorScheme.onSurfaceVariant),
                ),
              ),

              if (_showPageSize) ...[
                SizedBox(width: spacing.sm),

                Text(
                  'Show',
                  style: AppTextStyles.tiny(
                    context,
                  ).copyWith(color: colorScheme.onSurfaceVariant),
                ),

                SizedBox(width: spacing.xs),

                _PageSizeSelector(
                  value: pageSize!,
                  options: pageSizeOptions,
                  enabled: !isLoading,
                  onChanged: onPageSizeChanged!,
                ),

                SizedBox(width: spacing.xs),

                Text(
                  'per page',
                  style: AppTextStyles.tiny(
                    context,
                  ).copyWith(color: colorScheme.onSurfaceVariant),
                ),
              ],
            ],
          ),

          SizedBox(height: spacing.md),

          // ---------------------------------------------------------
          // PAGINATION NAVIGATION
          // ---------------------------------------------------------
          Row(
            children: [
              Expanded(
                child: _PaginationNavigationButton(
                  label: 'Previous',
                  icon: Icons.chevron_left_rounded,
                  iconLeading: true,
                  enabled: hasPrevious && !isLoading,
                  onPressed: onPrevious,
                ),
              ),

              SizedBox(width: spacing.sm),

              Expanded(
                child: _PageInformation(
                  page: safePage,
                  totalPages: safeTotalPages,
                  isLoading: isLoading,
                ),
              ),

              SizedBox(width: spacing.sm),

              Expanded(
                child: _PaginationNavigationButton(
                  label: 'Next',
                  icon: Icons.chevron_right_rounded,
                  iconLeading: false,
                  enabled: hasNext && !isLoading,
                  onPressed: onNext,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// PAGE INFORMATION
// -----------------------------------------------------------------------------

class _PageInformation extends StatelessWidget {
  const _PageInformation({
    required this.page,
    required this.totalPages,
    required this.isLoading,
  });

  final int page;
  final int totalPages;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    final colorScheme = context.colorScheme;
    final iconSize = context.iconSize;

    if (isLoading) {
      return Center(
        child: SizedBox(
          width: iconSize.small,
          height: iconSize.small,
          child: const CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }

    return Text(
      'Page $page of $totalPages',
      textAlign: TextAlign.center,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: AppTextStyles.tiny(context).copyWith(
        color: colorScheme.onSurfaceVariant,
        fontWeight: FontWeight.w700,
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// PREVIOUS / NEXT BUTTON
// -----------------------------------------------------------------------------

class _PaginationNavigationButton extends StatelessWidget {
  const _PaginationNavigationButton({
    required this.label,
    required this.icon,
    required this.iconLeading,
    required this.enabled,
    required this.onPressed,
  });

  final String label;
  final IconData icon;
  final bool iconLeading;
  final bool enabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    final radius = context.radius;
    final iconSize = context.iconSize;
    final colorScheme = context.colorScheme;

    final buttonColor = enabled
        ? colorScheme.primary
        : colorScheme.onSurface.withValues(alpha: 0.38);

    return TextButton(
      onPressed: enabled ? onPressed : null,
      style: TextButton.styleFrom(
        foregroundColor: buttonColor,
        disabledForegroundColor: buttonColor,
        minimumSize: const Size(0, 30),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        visualDensity: VisualDensity.compact,
        padding: EdgeInsets.symmetric(
          horizontal: spacing.sm,
          vertical: spacing.textButtonHeight,
        ),
        side: BorderSide(color: buttonColor, width: 1),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radius.cardRadius),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (iconLeading) ...[
            Icon(icon, size: iconSize.small, color: buttonColor),
            SizedBox(width: spacing.xs),
          ],
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyles.tiny(
                context,
              ).copyWith(color: buttonColor, fontWeight: FontWeight.w600),
            ),
          ),
          if (!iconLeading) ...[
            SizedBox(width: spacing.xs),
            Icon(icon, size: iconSize.small, color: buttonColor),
          ],
        ],
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// PAGE SIZE SELECTOR
// -----------------------------------------------------------------------------

class _PageSizeSelector extends StatelessWidget {
  const _PageSizeSelector({
    required this.value,
    required this.options,
    required this.enabled,
    required this.onChanged,
  });

  final int value;
  final List<int> options;
  final bool enabled;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    final radius = context.radius;
    final colorScheme = context.colorScheme;
    final iconSize = context.iconSize;

    final availableOptions = {...options, value}.toList()..sort();

    return Container(
      padding: EdgeInsets.symmetric(horizontal: spacing.sm),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(radius.sm),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.09),
        ),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<int>(
          value: value,
          isDense: true,
          icon: Icon(Icons.keyboard_arrow_down_rounded, size: iconSize.small),
          borderRadius: BorderRadius.circular(radius.md),
          dropdownColor: colorScheme.surfaceContainer,
          items: availableOptions.map((size) {
            return DropdownMenuItem<int>(
              value: size,
              child: Text('$size', style: AppTextStyles.tinyNumber(context)),
            );
          }).toList(),
          onChanged: enabled
              ? (selected) {
                  if (selected != null && selected != value) {
                    onChanged(selected);
                  }
                }
              : null,
        ),
      ),
    );
  }
}

// import 'package:flutter/material.dart';

// import 'package:ngoda/ui/extensions/app_size.dart';
// import 'package:ngoda/ui/extensions/theme_extension.dart';
// import 'package:ngoda/ui/shared/app_colors.dart';
// import 'package:ngoda/ui/shared/app_text_styles.dart';

// class AppPagination extends StatelessWidget {
//   const AppPagination({
//     super.key,
//     required this.page,
//     required this.totalPages,
//     required this.totalEntries,
//     required this.hasPrevious,
//     required this.hasNext,
//     required this.onPrevious,
//     required this.onNext,
//     this.isLoading = false,
//     this.entryLabel = 'items',
//     this.pageSize,
//     this.pageSizeOptions = const [25, 50, 100],
//     this.onPageSizeChanged,
//   });

//   final int page;
//   final int totalPages;
//   final int totalEntries;

//   final bool hasPrevious;
//   final bool hasNext;
//   final bool isLoading;

//   final VoidCallback onPrevious;
//   final VoidCallback onNext;

//   final String entryLabel;

//   final int? pageSize;
//   final List<int> pageSizeOptions;
//   final ValueChanged<int>? onPageSizeChanged;

//   bool get _showPageSize {
//     return pageSize != null && onPageSizeChanged != null;
//   }

//   @override
//   Widget build(BuildContext context) {
//     if (totalEntries == 0) {
//       return const SizedBox.shrink();
//     }

//     final spacing = context.spacing;
//     final radius = context.radius;
//     final colorScheme = context.colorScheme;

//     final safeTotalPages = totalPages > 0 ? totalPages : 1;

//     return Column(
//       mainAxisSize: MainAxisSize.min,
//       children: [
//         if (_showPageSize) ...[
//           Row(
//             children: [
//               Expanded(
//                 child: Text(
//                   '$totalEntries $entryLabel',
//                   style: AppTextStyles.tiny(
//                     context,
//                   ).copyWith(color: colorScheme.onSurfaceVariant),
//                 ),
//               ),

//               Text(
//                 'Show',
//                 style: AppTextStyles.tiny(
//                   context,
//                 ).copyWith(color: colorScheme.onSurfaceVariant),
//               ),

//               SizedBox(width: spacing.xs),

//               _PageSizeSelector(
//                 value: pageSize!,
//                 options: pageSizeOptions,
//                 enabled: !isLoading,
//                 onChanged: onPageSizeChanged!,
//               ),

//               SizedBox(width: spacing.xs),

//               Text(
//                 'per page',
//                 style: AppTextStyles.tiny(
//                   context,
//                 ).copyWith(color: colorScheme.onSurfaceVariant),
//               ),
//             ],
//           ),

//           SizedBox(height: spacing.sm),
//         ],

//         Container(
//           margin: EdgeInsets.symmetric(
//             horizontal: spacing.sm,
//             vertical: spacing.sm,
//           ),
//           width: double.infinity,
//           padding: EdgeInsets.symmetric(
//             horizontal: spacing.sm,
//             vertical: spacing.sm,
//           ),
//           decoration: BoxDecoration(
//             color: AppColors.darkCard,
//             borderRadius: BorderRadius.circular(radius.sm),
//           ),
//           child: Row(
//             children: [
//               _PaginationButton(
//                 icon: Icons.chevron_left,
//                 tooltip: 'Previous page',
//                 enabled: hasPrevious && !isLoading,
//                 onPressed: onPrevious,
//               ),

//               SizedBox(width: spacing.sm),

//               Expanded(
//                 child: _PageInformation(
//                   page: page,
//                   totalPages: safeTotalPages,
//                   totalEntries: totalEntries,
//                   entryLabel: entryLabel,
//                   isLoading: isLoading,
//                 ),
//               ),

//               SizedBox(width: spacing.sm),

//               _PaginationButton(
//                 icon: Icons.chevron_right,
//                 tooltip: 'Next page',
//                 enabled: hasNext && !isLoading,
//                 onPressed: onNext,
//               ),
//             ],
//           ),
//         ),
//       ],
//     );
//   }
// }

// class _PageInformation extends StatelessWidget {
//   const _PageInformation({
//     required this.page,
//     required this.totalPages,
//     required this.totalEntries,
//     required this.entryLabel,
//     required this.isLoading,
//   });

//   final int page;
//   final int totalPages;
//   final int totalEntries;
//   final String entryLabel;
//   final bool isLoading;

//   @override
//   Widget build(BuildContext context) {
//     final spacing = context.spacing;
//     final iconSize = context.iconSize;
//     final colorScheme = context.colorScheme;

//     return Column(
//       mainAxisSize: MainAxisSize.min,
//       children: [
//         if (isLoading)
//           SizedBox(
//             width: iconSize.small,
//             height: iconSize.small,
//             child: const CircularProgressIndicator(strokeWidth: 2),
//           )
//         else
//           Text(
//             'Page $page of $totalPages',
//             textAlign: TextAlign.center,
//             style: AppTextStyles.tiny(
//               context,
//             ).copyWith(fontWeight: FontWeight.w700),
//           ),

//         SizedBox(height: spacing.xs),

//         Text(
//           '$totalEntries $entryLabel',
//           textAlign: TextAlign.center,
//           style: AppTextStyles.tinyNumber(
//             context,
//           ).copyWith(color: colorScheme.onSurfaceVariant),
//         ),
//       ],
//     );
//   }
// }

// class _PaginationButton extends StatelessWidget {
//   const _PaginationButton({
//     required this.icon,
//     required this.tooltip,
//     required this.enabled,
//     required this.onPressed,
//   });

//   final IconData icon;
//   final String tooltip;
//   final bool enabled;
//   final VoidCallback onPressed;

//   @override
//   Widget build(BuildContext context) {
//     final spacing = context.spacing;
//     final radius = context.radius;
//     final iconSize = context.iconSize;

//     final backgroundColor = enabled
//         ? AppColors.darkBackground
//         : AppColors.darkBackground.withValues(alpha: 0.15);

//     final foregroundColor = enabled
//         ? AppColors.darkPrimary
//         : AppColors.darkPrimary.withValues(alpha: 0.45);

//     return Tooltip(
//       message: tooltip,
//       child: Material(
//         color: backgroundColor,
//         borderRadius: BorderRadius.circular(radius.sm),
//         child: InkWell(
//           onTap: enabled ? onPressed : null,
//           borderRadius: BorderRadius.circular(radius.sm),
//           child: SizedBox(
//             width: spacing.xl,
//             height: spacing.xl,
//             child: Center(
//               child: Icon(icon, size: iconSize.small, color: foregroundColor),
//             ),
//           ),
//         ),
//       ),
//     );
//   }
// }

// class _PageSizeSelector extends StatelessWidget {
//   const _PageSizeSelector({
//     required this.value,
//     required this.options,
//     required this.enabled,
//     required this.onChanged,
//   });

//   final int value;
//   final List<int> options;
//   final bool enabled;
//   final ValueChanged<int> onChanged;

//   @override
//   Widget build(BuildContext context) {
//     final spacing = context.spacing;
//     final radius = context.radius;
//     final colorScheme = context.colorScheme;

//     return Container(
//       padding: EdgeInsets.symmetric(horizontal: spacing.sm),
//       decoration: BoxDecoration(
//         color: colorScheme.surfaceContainerHighest,
//         borderRadius: BorderRadius.circular(radius.sm),
//       ),
//       child: DropdownButtonHideUnderline(
//         child: DropdownButton<int>(
//           value: value,
//           isDense: true,
//           items: options
//               .map(
//                 (size) => DropdownMenuItem<int>(
//                   value: size,
//                   child: Text(
//                     '$size',
//                     style: AppTextStyles.tinyNumber(context),
//                   ),
//                 ),
//               )
//               .toList(),
//           onChanged: enabled
//               ? (selected) {
//                   if (selected != null) {
//                     onChanged(selected);
//                   }
//                 }
//               : null,
//         ),
//       ),
//     );
//   }
// }
