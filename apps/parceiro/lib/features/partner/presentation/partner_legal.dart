import 'package:flutter/material.dart';
import 'package:scapematch/app/theme.dart';
import 'package:scapematch/core/ui/app_scaffold.dart';
import 'package:scapematch/features/legal/legal_documents.dart';

/// Termos da casa. Ficam neste app para não entrar no bundle do jogador.
abstract final class PartnerLegal {
  static const termsTitle = 'Termos do Parceiro';

  static const termsRequired =
      'Aceite os termos do Parceiro, a privacidade e a política de cancelamento para cadastrar a casa.';

  static const termsBody = '''
O ScapeMatch é uma intermediadora. A casa realiza a sessão. O ScapeMatch junta os jogadores, divide a reserva e cobra a parte de cada pessoa quando o grupo fecha.

Comissão. A comissão incide só sobre as reservas feitas pelo ScapeMatch. Ela é configurada pela plataforma e fica fotografada na reserva. O que a casa vende por fora não entra nessa conta. A comissão não é escondida do extrato da casa: o bruto, a comissão e o líquido aparecem separados.

Responsabilidade pela sessão. A casa responde pela sessão: segurança, equipe, horário, regras do jogo e o que acontece dentro do espaço. O ScapeMatch não opera a sala e não substitui a casa perante o jogador quanto à experiência.

Responsabilidade pela nota. Quando a casa tem CNPJ ou MEI e informa inscrição municipal, código de serviço e alíquota de ISS, ela emite a NFS-e do serviço para o jogador, pela subconta dela. Casa com CPF recebe o valor e fica marcada como sem emissão de nota. A ScapeMatch emite apenas a NFS-e da comissão, contra a casa. A casa não emite a nota da comissão, e o jogador não recebe essa nota.

Pagamento. O Pix pago é estornado se o grupo não fechar. A autorização do cartão não é capturada se o grupo não fechar. A casa só reconhece como receita da sessão o que tiver sido confirmado.

Ao cadastrar a casa você confirma que leu este rascunho, a política de privacidade e a política de cancelamento e reembolso. O aceite fica registrado com a versão do texto e a data.
''';
}

class PartnerLegalScreen extends StatelessWidget {
  const PartnerLegalScreen({super.key, required this.title, required this.body});

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final status = ScapeStatusColors.of(context);
    return AppScaffold(
      desktopMaxWidth: AppScaffold.readingMax,
      appBar: AppBar(
        title: Text(title),
        leading: const BackButton(),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
        children: [
          Text(
            LegalDocuments.reviewBanner,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: status.onAlertContainer,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 16),
          Text(body.trim(), style: theme.textTheme.bodyLarge),
        ],
      ),
    );
  }
}
