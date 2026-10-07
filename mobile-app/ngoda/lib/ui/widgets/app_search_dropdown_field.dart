import 'package:flutter/material.dart';
import 'package:ngoda/ui/extensions/app_size.dart';
import 'package:ngoda/ui/extensions/theme_extension.dart';
import 'package:ngoda/ui/shared/app_text_styles.dart';

class AppSearchDropdownField<T> extends StatefulWidget {
  final T? selected;
  final List<T> values;

  final String hint;

  final String Function(T value) displayText;

  final bool Function(T value, String query) filter;

  final ValueChanged<T> onSelect;

  final Widget Function(BuildContext context, T value)? itemBuilder;

  const AppSearchDropdownField({
    super.key,
    required this.selected,
    required this.values,
    required this.hint,
    required this.displayText,
    required this.filter,
    required this.onSelect,
    this.itemBuilder,
  });

  @override
  State<AppSearchDropdownField<T>> createState() {
    return _AppSearchDropdownFieldState<T>();
  }
}

class _AppSearchDropdownFieldState<T> extends State<AppSearchDropdownField<T>> {
  final TextEditingController _controller = TextEditingController();

  final FocusNode _focusNode = FocusNode();

  bool _showDropdown = false;

  List<T> get _filtered {
    final query = _controller.text.trim().toLowerCase();

    if (query.isEmpty) {
      return widget.values;
    }

    return widget.values.where((value) {
      return widget.filter(value, query);
    }).toList();
  }

  @override
  void initState() {
    super.initState();

    _syncSelection();

    _focusNode.addListener(_handleFocusChanged);
  }

  @override
  void didUpdateWidget(covariant AppSearchDropdownField<T> oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (widget.selected != oldWidget.selected) {
      _syncSelection();
    }
  }

  void _syncSelection() {
    final selected = widget.selected;

    if (selected == null) {
      _controller.clear();
      return;
    }

    _controller.text = widget.displayText(selected);
  }

  void _handleFocusChanged() {
    if (!mounted) {
      return;
    }

    setState(() {
      _showDropdown = _focusNode.hasFocus;
    });
  }

  void _select(T value) {
    _controller.text = widget.displayText(value);

    setState(() {
      _showDropdown = false;
    });

    _focusNode.unfocus();

    widget.onSelect(value);
  }

  @override
  void dispose() {
    _focusNode
      ..removeListener(_handleFocusChanged)
      ..dispose();

    _controller.dispose();

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final spacing = context.spacing;
    final radius = context.radius;
    final iconSize = context.iconSize;
    final colorScheme = context.colorScheme;

    final values = _filtered;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _controller,
          focusNode: _focusNode,
          style: AppTextStyles.small(context),
          decoration: InputDecoration(
            labelText: widget.hint,
            suffixIcon: Icon(
              Icons.search_rounded,
              color: colorScheme.primary,
              size: iconSize.medium,
            ),
          ),
          onTap: () {
            setState(() {
              _showDropdown = true;
            });
          },
          onChanged: (_) {
            setState(() {
              _showDropdown = true;
            });
          },
        ),

        if (_showDropdown) ...[
          SizedBox(height: spacing.xs),

          Material(
            color: context.theme.cardColor,
            borderRadius: BorderRadius.circular(radius.borderRadius),
            clipBehavior: Clip.antiAlias,
            child: Container(
              constraints: BoxConstraints(maxHeight: spacing.xxxxl * 3),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(radius.borderRadius),
                border: Border.all(
                  color: colorScheme.primary.withValues(alpha: 0.20),
                ),
              ),
              child: values.isEmpty
                  ? Padding(
                      padding: EdgeInsets.all(spacing.padding),
                      child: Text(
                        'No results found',
                        style: AppTextStyles.small(
                          context,
                        ).copyWith(color: colorScheme.onSurfaceVariant),
                      ),
                    )
                  : ListView.builder(
                      shrinkWrap: true,
                      padding: EdgeInsets.zero,
                      itemCount: values.length,
                      itemBuilder: (context, index) {
                        final value = values[index];

                        return InkWell(
                          onTap: () {
                            _select(value);
                          },
                          child:
                              widget.itemBuilder?.call(context, value) ??
                              Padding(
                                padding: EdgeInsets.all(spacing.padding),
                                child: Text(
                                  widget.displayText(value),
                                  style: AppTextStyles.small(context),
                                ),
                              ),
                        );
                      },
                    ),
            ),
          ),
        ],
      ],
    );
  }
}
