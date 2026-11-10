import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:scapematch_admin/admin_theme.dart';

/// Seis quadradinhos para o código TOTP.
///
/// Um único campo por trás dos quadradinhos: colar, teclado numérico e o
/// preenchimento automático do celular (oneTimeCode) entregam os 6 dígitos
/// de uma vez. Seis campos separados quebram esse preenchimento. O pacote
/// pinput faz a mesma coisa por baixo, com animação; aqui o desenho fica no
/// tema do Admin, sem dependência nova.
class AdminOtpField extends StatefulWidget {
  const AdminOtpField({
    super.key,
    required this.controller,
    required this.onCompleted,
    this.enabled = true,
    this.hasError = false,
  });

  final TextEditingController controller;
  final ValueChanged<String> onCompleted;
  final bool enabled;
  final bool hasError;

  @override
  State<AdminOtpField> createState() => _AdminOtpFieldState();
}

class _AdminOtpFieldState extends State<AdminOtpField> {
  final _focus = FocusNode();
  String? _done;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onController);
  }

  @override
  void didUpdateWidget(AdminOtpField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onController);
      widget.controller.addListener(_onController);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onController);
    _focus.dispose();
    super.dispose();
  }

  void _onController() {
    if (!mounted) return;
    if (widget.controller.text.length < 6) _done = null;
    setState(() {});
  }

  void _changed(String value) {
    _keepCursorAtEnd();
    if (!widget.enabled || value.length != 6 || value == _done) return;
    _done = value;
    widget.onCompleted(value);
  }

  void _keepCursorAtEnd() {
    final text = widget.controller.text;
    final end = TextSelection.collapsed(offset: text.length);
    if (widget.controller.selection != end) {
      widget.controller.selection = end;
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final code = widget.controller.text;
    return LayoutBuilder(
      builder: (context, constraints) {
        const gap = 8.0;
        const count = 6;
        final width = constraints.maxWidth;
        final box = ((width - gap * (count - 1)) / count).clamp(36.0, 52.0);
        final active = code.length < count ? code.length : count - 1;
        return SizedBox(
          height: box + 8,
          child: Stack(
            alignment: Alignment.center,
            children: [
              ExcludeSemantics(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    for (var i = 0; i < count; i++) ...[
                      if (i > 0) const SizedBox(width: gap),
                      _Box(
                        size: box,
                        digit: i < code.length ? code[i] : null,
                        active:
                            widget.enabled &&
                            i == active &&
                            code.length < count,
                        filled: i < code.length,
                        hasError: widget.hasError,
                        errorColor: scheme.error,
                        index: i,
                      ),
                    ],
                  ],
                ),
              ),
              Positioned.fill(
                child: TextField(
                  key: const Key('admin-mfa-code'),
                  controller: widget.controller,
                  focusNode: _focus,
                  enabled: widget.enabled,
                  autofocus: true,
                  autofillHints: const [AutofillHints.oneTimeCode],
                  keyboardType: TextInputType.number,
                  textInputAction: TextInputAction.done,
                  textAlign: TextAlign.center,
                  showCursor: false,
                  enableSuggestions: false,
                  autocorrect: false,
                  smartDashesType: SmartDashesType.disabled,
                  smartQuotesType: SmartQuotesType.disabled,
                  style: const TextStyle(
                    color: Colors.transparent,
                    fontSize: 1,
                  ),
                  cursorColor: Colors.transparent,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(count),
                  ],
                  decoration: const InputDecoration(
                    filled: false,
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    disabledBorder: InputBorder.none,
                    errorBorder: InputBorder.none,
                    focusedErrorBorder: InputBorder.none,
                    counterText: '',
                    contentPadding: EdgeInsets.zero,
                    hintText: 'Código de 6 dígitos do autenticador',
                    hintStyle: TextStyle(
                      color: Colors.transparent,
                      fontSize: 1,
                    ),
                    labelText: 'Código de 6 dígitos do autenticador',
                    floatingLabelBehavior: FloatingLabelBehavior.always,
                    floatingLabelStyle: TextStyle(
                      fontSize: 0.01,
                      height: 0.01,
                      color: Colors.transparent,
                    ),
                  ),
                  onChanged: _changed,
                  onTap: _keepCursorAtEnd,
                  onSubmitted: widget.enabled ? widget.onCompleted : null,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _Box extends StatelessWidget {
  const _Box({
    required this.size,
    required this.digit,
    required this.active,
    required this.filled,
    required this.hasError,
    required this.errorColor,
    required this.index,
  });

  final double size;
  final String? digit;
  final bool active;
  final bool filled;
  final bool hasError;
  final Color errorColor;
  final int index;

  @override
  Widget build(BuildContext context) {
    final borderColor = hasError
        ? errorColor
        : active
        ? adminTeal
        : const Color(0xFFE7E0D8);
    return Container(
      key: Key(active ? 'admin-otp-active-$index' : 'admin-otp-box-$index'),
      width: size,
      height: size + 4,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: filled ? const Color(0xFFF3FAF8) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: borderColor,
          width: active || hasError ? 2 : 1,
        ),
      ),
      child: digit == null
          ? null
          : Text(
              digit!,
              key: Key('admin-otp-digit-$index'),
              style: TextStyle(
                color: adminTeal,
                fontFamily: 'Poppins',
                fontWeight: FontWeight.w500,
                fontSize: size * 0.46,
              ),
            ),
    );
  }
}
