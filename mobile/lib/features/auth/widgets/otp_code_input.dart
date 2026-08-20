import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/app_theme.dart';

class OtpCodeInput extends StatefulWidget {
  const OtpCodeInput({
    super.key,
    required this.digitLabel,
    required this.onChanged,
    required this.onCompleted,
    this.initialCode = '',
    this.enabled = true,
  });

  final String Function(int position) digitLabel;
  final ValueChanged<String> onChanged;
  final ValueChanged<String> onCompleted;
  final String initialCode;
  final bool enabled;

  @override
  State<OtpCodeInput> createState() => OtpCodeInputState();
}

class OtpCodeInputState extends State<OtpCodeInput> {
  static const _length = 6;

  late final List<TextEditingController> _controllers;
  late final List<FocusNode> _focusNodes;
  bool _updating = false;

  @override
  void initState() {
    super.initState();
    _controllers = List.generate(_length, (_) => TextEditingController());
    _focusNodes = List.generate(_length, (_) => FocusNode());
    final initialDigits = widget.initialCode.replaceAll(RegExp(r'\D'), '');
    if (initialDigits.isNotEmpty) {
      _setCode(initialDigits, notify: false);
    }
  }

  @override
  void dispose() {
    for (final controller in _controllers) {
      controller.dispose();
    }
    for (final focusNode in _focusNodes) {
      focusNode.dispose();
    }
    super.dispose();
  }

  String get code => _controllers.map((controller) => controller.text).join();

  void clear({bool notify = true}) {
    _updating = true;
    for (final controller in _controllers) {
      controller.clear();
    }
    _updating = false;
    if (notify) widget.onChanged('');
    _focusNodes.first.requestFocus();
  }

  void _setCode(String value, {bool notify = true}) {
    final normalized = value.replaceAll(RegExp(r'\D'), '');
    final digits = normalized.length > _length ? normalized.substring(0, _length) : normalized;
    _updating = true;
    for (var index = 0; index < _length; index += 1) {
      final digit = index < digits.length ? digits[index] : '';
      _controllers[index].value = TextEditingValue(
        text: digit,
        selection: TextSelection.collapsed(offset: digit.length),
      );
    }
    _updating = false;

    if (digits.length == _length) {
      _focusNodes.last.unfocus();
    } else {
      _focusNodes[digits.length].requestFocus();
    }
    if (notify) _notify();
  }

  void _notify() {
    final value = code;
    widget.onChanged(value);
    if (value.length == _length) widget.onCompleted(value);
  }

  void _onChanged(int index, String value) {
    if (_updating) return;
    final digits = value.replaceAll(RegExp(r'\D'), '');
    if (digits.length > 1) {
      _setCode(digits);
      return;
    }

    if (value != digits) {
      _controllers[index].value = TextEditingValue(
        text: digits,
        selection: TextSelection.collapsed(offset: digits.length),
      );
    }

    if (digits.isNotEmpty && index < _length - 1) {
      _focusNodes[index + 1].requestFocus();
    } else if (digits.isEmpty && index > 0) {
      _focusNodes[index - 1].requestFocus();
    }
    _notify();
  }

  KeyEventResult _onKeyEvent(int index, KeyEvent event) {
    if (event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.backspace &&
        _controllers[index].text.isEmpty &&
        index > 0) {
      _controllers[index - 1].clear();
      _focusNodes[index - 1].requestFocus();
      _notify();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Directionality(
      textDirection: TextDirection.ltr,
      child: AutofillGroup(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final gap = constraints.maxWidth < AppTheme.compactBreakpoint
                ? AppTheme.space2xs
                : AppTheme.spaceXs;
            return Row(
              children: List.generate(_length, (index) {
                return Expanded(
                  child: Padding(
                    padding: EdgeInsetsDirectional.only(
                      end: index == _length - 1 ? 0 : gap,
                    ),
                    child: Semantics(
                      label: widget.digitLabel(index + 1),
                      textField: true,
                      child: Focus(
                        onKeyEvent: (_, event) => _onKeyEvent(index, event),
                        child: TextField(
                          controller: _controllers[index],
                          focusNode: _focusNodes[index],
                          enabled: widget.enabled,
                          autofocus: index == 0 && widget.initialCode.isEmpty,
                          keyboardType: TextInputType.number,
                          textInputAction: index == _length - 1 ? TextInputAction.done : TextInputAction.next,
                          textAlign: TextAlign.center,
                          textDirection: TextDirection.ltr,
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: AppTheme.weightBold,
                          ),
                          autofillHints: index == 0 ? const [AutofillHints.oneTimeCode] : null,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                            LengthLimitingTextInputFormatter(_length),
                          ],
                          decoration: const InputDecoration(
                            counterText: '',
                            contentPadding: EdgeInsets.symmetric(
                              horizontal: AppTheme.space2xs,
                              vertical: AppTheme.spaceLg,
                            ),
                          ),
                          onChanged: (value) => _onChanged(index, value),
                        ),
                      ),
                    ),
                  ),
                );
              }),
            );
          },
        ),
      ),
    );
  }
}
