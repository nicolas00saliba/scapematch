import 'package:flutter/material.dart';

/// Aviso fixo no alto da tela: o resultado de um botão aparece onde o dedo
/// está, e não no fim de uma página longa. Erro vem em vermelho.
class AdminNotice extends StatelessWidget {
  const AdminNotice({
    super.key,
    required this.text,
    this.error = false,
    this.onClose,
    this.textKey,
  });

  final Key? textKey;
  final String text;
  final bool error;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final background = error ? scheme.errorContainer : const Color(0xFFDCF1E4);
    final foreground = error
        ? scheme.onErrorContainer
        : const Color(0xFF14532D);
    return Semantics(
      liveRegion: true,
      container: true,
      child: Material(
        color: background,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
          child: Row(
            children: [
              Icon(
                error ? Icons.error_outline : Icons.check_circle_outline,
                color: foreground,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  text,
                  key: textKey,
                  style: TextStyle(color: foreground),
                ),
              ),
              if (onClose != null)
                IconButton(
                  tooltip: 'Fechar aviso',
                  onPressed: onClose,
                  icon: Icon(Icons.close, color: foreground),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
