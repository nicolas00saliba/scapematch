import 'package:flutter/material.dart';
import 'package:scapematch/app/theme.dart';
import 'package:scapematch/core/mode/app_mode.dart';
import 'package:scapematch/core/supabase/scape_backend.dart';

/// Aviso curto. Aberto, explica que tudo nesta versão é inventado.
class ExampleDataBanner extends StatefulWidget {
  const ExampleDataBanner({super.key});

  @override
  State<ExampleDataBanner> createState() => _ExampleDataBannerState();
}

class _ExampleDataBannerState extends State<ExampleDataBanner> {
  var _open = false;

  void _alternar() => setState(() => _open = !_open);

  @override
  Widget build(BuildContext context) {
    if (!kShowDemoChrome || scapeUsesLiveBackend) {
      return const SizedBox.shrink();
    }
    final status = ScapeStatusColors.of(context);
    final textStyle = TextStyle(
      color: status.onAlertContainer,
      height: 1.3,
      fontWeight: FontWeight.w600,
      fontSize: 13,
    );
    final selo = Material(
      color: status.alertContainer,
      borderRadius: BorderRadius.circular(20),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: _open
            ? ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 280),
                child: Text(
                  'Demonstração. Casas, salas, horários, grupos e notícias são fictícios.',
                  style: textStyle,
                ),
              )
            : FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.info_outline,
                      color: status.alert,
                      size: 16,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Demonstração',
                      maxLines: 1,
                      style: textStyle.copyWith(fontWeight: FontWeight.w700),
                    ),
                  ],
                ),
              ),
      ),
    );
    return Align(
      alignment: Alignment.centerLeft,
      child: Semantics(
        button: true,
        onTap: _alternar,
        label: _open
            ? 'Demonstração. Os dados desta versão são fictícios. Toque para recolher.'
            : 'Demonstração. Toque para ler o aviso.',
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48),
          child: Stack(
            alignment: Alignment.topLeft,
            children: [
              const SizedBox(width: double.infinity, height: 48),
              selo,
              Positioned.fill(
                child: Material(
                  type: MaterialType.transparency,
                  child: InkWell(
                    excludeFromSemantics: true,
                    onTap: _alternar,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
