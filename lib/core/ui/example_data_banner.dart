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
    return Align(
      alignment: Alignment.centerLeft,
      child: Semantics(
        button: true,
        label: _open
            ? 'Aviso: os dados desta versão são fictícios e servem só como exemplo. Toque para recolher.'
            : 'Aviso: os dados desta versão são fictícios e servem só como exemplo. Toque para ler.',
        child: Material(
          color: AppColors.copperSoft,
          borderRadius: BorderRadius.circular(20),
          child: InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: () => setState(() => _open = !_open),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              child: _open
                  ? ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 280),
                      child: const Text(
                        'Dados de exemplo. Casas, salas, horários, grupos e notícias são fictícios.',
                        style: TextStyle(
                          color: AppColors.copperInk,
                          height: 1.3,
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
                    )
                  : const FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.info_outline,
                            color: AppColors.copper,
                            size: 16,
                          ),
                          SizedBox(width: 6),
                          Text(
                            'Dados de exemplo',
                            maxLines: 1,
                            style: TextStyle(
                              color: AppColors.copperInk,
                              fontWeight: FontWeight.w700,
                              fontSize: 13,
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
