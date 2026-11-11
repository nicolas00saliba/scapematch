import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:scapematch/features/scape_points/domain/scape_wallet.dart';
import 'package:scapematch_admin/admin_format.dart';
import 'package:scapematch_admin/admin_theme.dart';

/// Como o número salvo em referral_program_settings aparece no formulário.
/// O valor gravado não muda: pontos-base continuam com 10000 = 100%.
enum RewardKind { basisPoints, playerPoints, pointValue, count, cents }

class RewardField {
  const RewardField({
    required this.id,
    required this.label,
    required this.help,
    required this.kind,
    this.section,
    this.percentOf = '',
    this.one = '',
    this.many = '',
    this.zeroMeansOff = false,
    this.playerSeesPoints = false,
  });

  final String id;
  final String? section;
  final String label;
  final String help;
  final RewardKind kind;

  /// Complemento da porcentagem: "da reserva", "do extra", "a mais".
  final String percentOf;
  final String one;
  final String many;
  final bool zeroMeansOff;

  /// O jogador vê pontos. O texto lembra quanto vale 1 ponto.
  final bool playerSeesPoints;
}

const rewardFields = <RewardField>[
  RewardField(
    id: 'c2c_bps',
    section: 'Indicações',
    label: 'Indicação de jogador para jogador',
    help: 'Fatia da reserva que vira pontos para quem indicou o jogador. Ele vê esses pontos no extrato, depois da carência.',
    kind: RewardKind.basisPoints,
    percentOf: 'da reserva',
    playerSeesPoints: true,
  ),
  RewardField(
    id: 'b2c_bps',
    label: 'Indicação de casa para jogador',
    help: 'Fatia da reserva creditada à casa que indicou o jogador, quando ele joga em outra casa. A casa vê crédito em reais, não pontos.',
    kind: RewardKind.basisPoints,
    percentOf: 'da reserva',
  ),
  RewardField(
    id: 'c2b_bps',
    label: 'Indicação de jogador para casa',
    help: 'Fatia do faturamento da casa que vira pontos para o jogador que a indicou. Ele vê esses pontos no extrato, depois da carência.',
    kind: RewardKind.basisPoints,
    percentOf: 'da reserva',
    playerSeesPoints: true,
  ),
  RewardField(
    id: 'b2b_bps',
    label: 'Indicação de casa para casa',
    help: 'Fatia da reserva creditada à casa que indicou a outra. Não entra quando a reserva tem desconto de primeira visita.',
    kind: RewardKind.basisPoints,
    percentOf: 'da reserva',
  ),
  RewardField(
    id: 'cashback_bps',
    section: 'Cashback',
    label: 'Cashback do pagador',
    help: 'Referência sobre o valor pago. O jogador vê em pontos o cashback sorteado, limitado à comissão que sobrou.',
    kind: RewardKind.basisPoints,
    percentOf: 'do valor pago',
    playerSeesPoints: true,
  ),
  RewardField(
    id: 'redeem_min_points',
    section: 'Resgate e boas-vindas',
    label: 'Mínimo para resgatar',
    help: 'Pontos livres que o jogador precisa juntar antes de usar o saldo numa sala.',
    kind: RewardKind.playerPoints,
    playerSeesPoints: true,
  ),
  RewardField(
    id: 'redeem_max_bps',
    label: 'Teto do resgate',
    help: 'Máximo da reserva que pode ser pago com pontos. O jogador vê o desconto em pontos, sem passar deste percentual.',
    kind: RewardKind.basisPoints,
    percentOf: 'da reserva',
    playerSeesPoints: true,
  ),
  RewardField(
    id: 'welcome_points',
    label: 'Boas-vindas',
    help: 'Pontos creditados uma vez, quando o jogador informa o CPF. Ele vê esse saldo na hora.',
    kind: RewardKind.playerPoints,
    playerSeesPoints: true,
  ),
  RewardField(
    id: 'empty_slot_house_share_bps',
    section: 'Horário vazio',
    label: 'Parte da casa no horário vazio',
    help: 'No horário vazio o cashback dobra. Esta parte do extra sai da casa; o resto sai da comissão. O jogador vê o dobro em pontos.',
    kind: RewardKind.basisPoints,
    percentOf: 'do extra',
    playerSeesPoints: true,
  ),
  RewardField(
    id: 'tier_silver_active',
    section: 'Níveis',
    label: 'Indicações ativas para prata',
    help: 'Indicações com pagamento dentro da janela para o jogador chegar à prata. Ele vê o nível no extrato.',
    kind: RewardKind.count,
    one: 'indicação',
    many: 'indicações',
  ),
  RewardField(
    id: 'tier_silver_bonus_bps',
    label: 'Bônus da prata',
    help: 'Acréscimo nas indicações de jogador, no nível prata. O jogador vê os pontos já com esse bônus.',
    kind: RewardKind.basisPoints,
    percentOf: 'a mais',
    playerSeesPoints: true,
  ),
  RewardField(
    id: 'tier_gold_active',
    label: 'Indicações ativas para ouro',
    help: 'Indicações com pagamento dentro da janela para o nível ouro.',
    kind: RewardKind.count,
    one: 'indicação',
    many: 'indicações',
  ),
  RewardField(
    id: 'tier_gold_bonus_bps',
    label: 'Bônus do ouro',
    help: 'Acréscimo nas indicações de jogador, no nível ouro. O jogador vê os pontos já com esse bônus.',
    kind: RewardKind.basisPoints,
    percentOf: 'a mais',
    playerSeesPoints: true,
  ),
  RewardField(
    id: 'tier_active_days',
    label: 'Janela do nível',
    help: 'Por quantos dias um pagamento recente conta como indicação ativa para prata e ouro.',
    kind: RewardKind.count,
    one: 'dia',
    many: 'dias',
  ),
  RewardField(
    id: 'payer_referred_account_cap',
    section: 'Travas',
    label: 'Contas que um pagador pode premiar',
    help: 'Um mesmo pagador gera recompensa para no máximo este número de contas indicadas. Zero desliga. O cashback não entra nessa trava.',
    kind: RewardKind.count,
    one: 'conta',
    many: 'contas',
    zeroMeansOff: true,
  ),
  RewardField(
    id: 'same_device_review_threshold',
    label: 'Mesmo aparelho manda para revisão',
    help: 'Contas do mesmo indicador criadas no mesmo aparelho, a partir deste número, ficam em revisão. Zero desliga.',
    kind: RewardKind.count,
    one: 'conta',
    many: 'contas',
    zeroMeansOff: true,
  ),
  RewardField(
    id: 'point_value_cents',
    section: 'Valor e carência',
    label: 'Valor de cada ponto',
    help: 'Centavos de 1 ponto. O jogador vê o saldo em pontos; este valor converte para reais.',
    kind: RewardKind.pointValue,
  ),
  RewardField(
    id: 'hold_days',
    label: 'Carência',
    help: 'Dias até os pontos de indicação e de cashback ficarem livres para usar na sala. O crédito da casa espera o mesmo prazo.',
    kind: RewardKind.count,
    one: 'dia',
    many: 'dias',
  ),
];

RewardField rewardFieldById(String id) {
  return rewardFields.firstWhere((field) => field.id == id);
}

/// Leitura ao lado do número digitado. Não altera o que será gravado.
String rewardEquivalence({
  required RewardField field,
  required String raw,
  required int? pointValueCents,
}) {
  final value = int.tryParse(raw.trim());
  if (value == null) return '—';
  switch (field.kind) {
    case RewardKind.basisPoints:
      final percent = percentBps(value);
      final reading = field.percentOf.isEmpty
          ? percent
          : '$percent ${field.percentOf}';
      return '${formatPoints(value)} pontos-base = $reading';
    case RewardKind.playerPoints:
      final points = value == 1 ? '1 ponto' : '${formatPoints(value)} pontos';
      if (pointValueCents == null || pointValueCents < 1) return points;
      return '$points = ${reais(value * pointValueCents)}';
    case RewardKind.pointValue:
      if (value < 1) return '—';
      return '1 ponto = ${reais(value)}';
    case RewardKind.count:
      if (field.zeroMeansOff && value == 0) return 'desligado';
      final number = formatPoints(value);
      if (value == 1) return '$number ${field.one}';
      return '$number ${field.many}';
    case RewardKind.cents:
      return reais(value);
  }
}

String rewardHelp(RewardField field, int? pointValueCents) {
  if (!field.playerSeesPoints) return field.help;
  if (pointValueCents == null || pointValueCents < 1) {
    return '${field.help} Defina o valor de cada ponto para ver o real.';
  }
  return '${field.help} Cada ponto vale ${reais(pointValueCents)}.';
}

class RewardRuleTile extends StatelessWidget {
  const RewardRuleTile({
    super.key,
    required this.field,
    required this.controller,
    required this.pointValueCents,
    required this.onChanged,
  });

  final RewardField field;
  final TextEditingController controller;
  final int? pointValueCents;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final help = rewardHelp(field, pointValueCents);
    final aside = rewardEquivalence(
      field: field,
      raw: controller.text,
      pointValueCents: pointValueCents,
    );
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    final wide = MediaQuery.sizeOf(context).width >= 720;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ExcludeSemantics(
            child: Text(
              field.label,
              style: Theme.of(context).textTheme.titleSmall
                  ?.copyWith(fontWeight: FontWeight.w500),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            help,
            style: Theme.of(context).textTheme.bodySmall
                ?.copyWith(color: muted, height: 1.35),
          ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              SizedBox(
                width: wide ? 200 : 120,
                child: TextField(
                  key: Key('admin-regra-${field.id}'),
                  controller: controller,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  onChanged: onChanged,
                  decoration: InputDecoration(
                    isDense: true,
                    labelText: field.label,
                    floatingLabelBehavior: FloatingLabelBehavior.never,
                    labelStyle: const TextStyle(
                      fontSize: 0.01,
                      height: 0.01,
                      color: Colors.transparent,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: const Color(0xFFE7F0EF),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    child: Text(
                      aside,
                      key: Key('admin-regra-equiv-${field.id}'),
                      style: const TextStyle(
                        color: adminTeal,
                        fontWeight: FontWeight.w500,
                        height: 1.3,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
