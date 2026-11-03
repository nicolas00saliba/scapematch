import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:scapematch/core/ui/app_keys.dart';

/// Volta uma tela. Sem histórico, como num link aberto direto, vai para a Home.
void scapeBack(BuildContext context) {
  if (context.canPop()) {
    context.pop();
    return;
  }
  context.go('/');
}

/// Seta da barra. Sempre visível, no app e na web.
class ScapeBackButton extends StatelessWidget {
  const ScapeBackButton({super.key});

  @override
  Widget build(BuildContext context) {
    return BackButton(
      key: AppKeys.scapeBack,
      onPressed: () => scapeBack(context),
    );
  }
}

/// Seta sobre a capa: círculo translúcido, no canto superior esquerdo.
class ScapeCoverBackButton extends StatelessWidget {
  const ScapeCoverBackButton({super.key});

  @override
  Widget build(BuildContext context) {
    const ink = Color(0xFF1A1A1A);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 0, 0),
      child: DecoratedBox(
        decoration: const BoxDecoration(
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: Color(0x4D000000),
              blurRadius: 8,
              offset: Offset(0, 2),
            ),
          ],
        ),
        child: BackButton(
          key: AppKeys.scapeBack,
          color: ink,
          style: IconButton.styleFrom(
            backgroundColor: Colors.white.withValues(alpha: 0.92),
            foregroundColor: ink,
            fixedSize: const Size(44, 44),
            minimumSize: const Size(44, 44),
            shape: const CircleBorder(),
          ),
          onPressed: () => scapeBack(context),
        ),
      ),
    );
  }
}
