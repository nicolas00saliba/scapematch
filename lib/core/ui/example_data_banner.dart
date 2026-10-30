import 'package:flutter/material.dart';
import 'package:scapematch/app/theme.dart';

/// Aviso curto. Aberto, explica que tudo nesta versão é inventado.
class ExampleDataBanner extends StatefulWidget {
  const ExampleDataBanner({super.key});

  @override
  State<ExampleDataBanner> createState() => _ExampleDataBannerState();
}

class _ExampleDataBannerState extends State<ExampleDataBanner> {
  var _open = false;

  @override
  Widget build(BuildContext context) {
    final status = ScapeStatusColors.of(context);
    final textStyle = TextStyle(
      color: status.onAlertContainer,
      height: 1.3,
      fontWeight: FontWeight.w600,
      fontSize: 13,
    );
    return Align(
      alignment: Alignment.centerLeft,
      child: Semantics(
        button: true,
        label: _open
            ? 'Aviso: os dados desta versão são fictícios e servem só como exemplo. Toque para recolher.'
            : 'Aviso: os dados desta versão são fictícios e servem só como exemplo. Toque para ler.',
        child: Material(
          color: status.alertContainer,
          borderRadius: BorderRadius.circular(20),
          child: InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: () => setState(() => _open = !_open),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              child: _open
                  ? ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 280),
                      child: Text(
                        'Dados de exemplo. Casas, salas, horários, grupos e notícias são fictícios.',
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
                            'Dados de exemplo',
                            maxLines: 1,
                            style: textStyle.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
            ),
          ),
        ),
      ),
    );
  }
}
