import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:ngoda/ui/extensions/app_size.dart';
import 'package:ngoda/ui/extensions/theme_extension.dart';
import 'package:ngoda/ui/shared/app_text_styles.dart';

class InputField extends StatefulWidget {
  final TextEditingController controller;
  final String placeholder;

  final bool obscureText;
  final bool showPasswordToggle;
  final bool readOnly;
  final bool enabled;

  final TextInputType keyboardType;
  final TextInputAction? textInputAction;

  final ValueChanged<String>? onChanged;
  final VoidCallback? onTap;
  final ValueChanged<String>? onSubmitted;

  final Widget? prefixIcon;
  final Widget? suffixIcon;

  final List<TextInputFormatter>? inputFormatters;

  final int? maxLines;
  final int? minLines;
  final int? maxLength;

  const InputField({
    super.key,
    required this.controller,
    required this.placeholder,
    this.obscureText = false,
    this.showPasswordToggle = false,
    this.readOnly = false,
    this.enabled = true,
    this.keyboardType = TextInputType.text,
    this.textInputAction,
    this.onChanged,
    this.onTap,
    this.onSubmitted,
    this.prefixIcon,
    this.suffixIcon,
    this.inputFormatters,
    this.maxLines = 1,
    this.minLines,
    this.maxLength,
  });

  @override
  State<InputField> createState() {
    return _InputFieldState();
  }
}

class _InputFieldState extends State<InputField> {
  late bool _obscureText;

  @override
  void initState() {
    super.initState();

    _obscureText = widget.obscureText;
  }

  @override
  void didUpdateWidget(covariant InputField oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (widget.obscureText != oldWidget.obscureText) {
      _obscureText = widget.obscureText;
    }
  }

  bool get _isNumeric {
    return widget.keyboardType == TextInputType.number ||
        widget.keyboardType ==
            const TextInputType.numberWithOptions(decimal: true) ||
        widget.keyboardType ==
            const TextInputType.numberWithOptions(decimal: true, signed: true);
  }

  @override
  Widget build(BuildContext context) {
    final iconSize = context.iconSize;
    final colorScheme = context.colorScheme;

    final formatters =
        widget.inputFormatters ??
        (_isNumeric
            ? [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*$'))]
            : null);

    final suffix = widget.showPasswordToggle
        ? IconButton(
            tooltip: _obscureText ? 'Show password' : 'Hide password',
            icon: Icon(
              _obscureText
                  ? Icons.visibility_off_outlined
                  : Icons.visibility_outlined,
              size: iconSize.medium,
              color: colorScheme.primary,
            ),
            onPressed: widget.enabled
                ? () {
                    setState(() {
                      _obscureText = !_obscureText;
                    });
                  }
                : null,
          )
        : widget.suffixIcon;

    return TextField(
      controller: widget.controller,
      enabled: widget.enabled,
      readOnly: widget.readOnly,
      obscureText: _obscureText,
      keyboardType: widget.keyboardType,
      textInputAction: widget.textInputAction,
      onChanged: widget.onChanged,
      onTap: widget.onTap,
      onSubmitted: widget.onSubmitted,
      inputFormatters: formatters,
      maxLines: _obscureText ? 1 : widget.maxLines,
      minLines: _obscureText ? 1 : widget.minLines,
      maxLength: widget.maxLength,
      style: _isNumeric
          ? AppTextStyles.smallNumber(context)
          : AppTextStyles.small(context),
      decoration: InputDecoration(
        labelText: widget.placeholder,
        prefixIcon: widget.prefixIcon,
        suffixIcon: suffix,

        /*
         * maxLength is used to enforce the maximum
         * input length where required.
         *
         * Flutter displays a character counter whenever
         * maxLength is provided. Ngoda does not display
         * character counters on input fields.
         */
        counterText: '',
      ),
    );
  }
}
