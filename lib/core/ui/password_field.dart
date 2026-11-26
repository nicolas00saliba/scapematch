import 'package:flutter/material.dart';

/// Campo de senha com o olho que mostra e esconde o texto.
class PasswordField extends StatefulWidget {
  const PasswordField({
    super.key,
    this.fieldKey,
    required this.controller,
    this.labelText = 'Senha',
    this.helperText,
    this.errorText,
    this.autofillHints,
    this.onSubmitted,
    this.textInputAction,
  });

  final Key? fieldKey;
  final TextEditingController controller;
  final String labelText;
  final String? helperText;
  final String? errorText;
  final Iterable<String>? autofillHints;
  final ValueChanged<String>? onSubmitted;
  final TextInputAction? textInputAction;

  @override
  State<PasswordField> createState() => _PasswordFieldState();
}

class _PasswordFieldState extends State<PasswordField> {
  var _obscure = true;

  @override
  Widget build(BuildContext context) {
    final label = _obscure ? 'Mostrar senha' : 'Ocultar senha';
    return TextField(
      key: widget.fieldKey,
      controller: widget.controller,
      obscureText: _obscure,
      autofillHints: widget.autofillHints,
      textInputAction: widget.textInputAction,
      onSubmitted: widget.onSubmitted,
      decoration: InputDecoration(
        labelText: widget.labelText,
        helperText: widget.helperText,
        errorText: widget.errorText,
        border: const OutlineInputBorder(),
        suffixIcon: IconButton(
          tooltip: label,
          onPressed: () => setState(() => _obscure = !_obscure),
          icon: Icon(
            _obscure ? Icons.visibility : Icons.visibility_off,
            semanticLabel: label,
          ),
        ),
      ),
    );
  }
}
