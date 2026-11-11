import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scapematch/core/supabase/scape_backend.dart';
import 'package:scapematch_admin/admin_api.dart';
import 'package:scapematch_admin/admin_pages.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Interruptor, peso bayesiano e mínimo do ranking. Nasce desligado.
class ReviewSettings {
  const ReviewSettings({
    required this.enabled,
    required this.priorWeight,
    required this.rankingMinimum,
  });

  final bool enabled;
  final int priorWeight;
  final int rankingMinimum;

  static const defaults = ReviewSettings(
    enabled: false,
    priorWeight: 10,
    rankingMinimum: 10,
  );
}

class ModerationComment {
  const ModerationComment({
    required this.id,
    required this.firstName,
    required this.comment,
    required this.overall,
    required this.roomName,
    required this.venueName,
    required this.reports,
    required this.hidden,
    required this.hiddenReason,
  });

  final String id;
  final String firstName;
  final String comment;
  final double overall;
  final String roomName;
  final String venueName;
  final int reports;
  final bool hidden;
  final String hiddenReason;
}

class ModerationEvent {
  const ModerationEvent({
    required this.action,
    required this.reason,
    required this.reviewId,
  });

  final String action;
  final String reason;
  final String reviewId;
}

abstract class ReviewAdminApi {
  Future<ReviewSettings> settings();
  Future<ReviewSettings> save(ReviewSettings next);
  Future<List<ModerationComment>> queue();
  Future<void> hide({required String id, required String reason});
  Future<void> unhide({required String id, required String reason});
  Future<List<ModerationEvent>> audit();
}

class MemoryReviewAdminApi implements ReviewAdminApi {
  MemoryReviewAdminApi({ReviewSettings? settings})
    : _settings = settings ?? ReviewSettings.defaults;

  ReviewSettings _settings;
  final List<ModerationComment> _queue = [
    const ModerationComment(
      id: 'avaliacao-1',
      firstName: 'Ana',
      comment: 'A história prende, mas a sala estava abafada.',
      overall: 4,
      roomName: 'O Cofre',
      venueName: 'Ninja Escape',
      reports: 1,
      hidden: false,
      hiddenReason: '',
    ),
  ];
  final List<ModerationEvent> _audit = [];

  @override
  Future<ReviewSettings> settings() async => _settings;

  @override
  Future<ReviewSettings> save(ReviewSettings next) async {
    if (next.priorWeight < 1 || next.priorWeight > 1000) {
      throw AdminRejected('m fica entre 1 e 1000');
    }
    if (next.rankingMinimum < 1 || next.rankingMinimum > 10000) {
      throw AdminRejected('o mínimo fica entre 1 e 10000');
    }
    _settings = next;
    _audit.add(
      ModerationEvent(
        action: 'save',
        reason: next.enabled ? 'ligou' : 'desligou',
        reviewId: 'settings',
      ),
    );
    return _settings;
  }

  @override
  Future<List<ModerationComment>> queue() async => List.of(_queue);

  @override
  Future<void> hide({required String id, required String reason}) async {
    final text = reason.trim();
    if (text.isEmpty || text.length > 280) {
      throw AdminRejected('O motivo fica entre 1 e 280 caracteres.');
    }
    final index = _queue.indexWhere((item) => item.id == id);
    if (index < 0) throw AdminRejected('avaliação não encontrada');
    final current = _queue[index];
    _queue[index] = ModerationComment(
      id: current.id,
      firstName: current.firstName,
      comment: current.comment,
      overall: current.overall,
      roomName: current.roomName,
      venueName: current.venueName,
      reports: current.reports,
      hidden: true,
      hiddenReason: text,
    );
    _audit.add(ModerationEvent(action: 'hide', reason: text, reviewId: id));
  }

  @override
  Future<void> unhide({required String id, required String reason}) async {
    final text = reason.trim();
    if (text.isEmpty) {
      throw AdminRejected('O motivo fica entre 1 e 280 caracteres.');
    }
    final index = _queue.indexWhere((item) => item.id == id);
    if (index < 0) return;
    final current = _queue[index];
    _queue[index] = ModerationComment(
      id: current.id,
      firstName: current.firstName,
      comment: current.comment,
      overall: current.overall,
      roomName: current.roomName,
      venueName: current.venueName,
      reports: current.reports,
      hidden: false,
      hiddenReason: '',
    );
    _audit.add(ModerationEvent(action: 'unhide', reason: text, reviewId: id));
  }

  @override
  Future<List<ModerationEvent>> audit() async => List.of(_audit.reversed);
}

class SupabaseReviewAdminApi implements ReviewAdminApi {
  SupabaseReviewAdminApi(this.client);

  final SupabaseClient client;

  @override
  Future<ReviewSettings> settings() async {
    final raw = await _rpc('admin_review_settings');
    return _settings(raw);
  }

  @override
  Future<ReviewSettings> save(ReviewSettings next) async {
    final raw = await _rpc('admin_save_review_settings', {
      'p_patch': {
        'enabled': next.enabled,
        'bayesian_m': next.priorWeight,
        'ranking_min': next.rankingMinimum,
      },
    });
    return _settings(raw);
  }

  @override
  Future<List<ModerationComment>> queue() async {
    final raw = await _rpc('admin_review_queue');
    if (raw is! List) return const [];
    return [
      for (final item in raw)
        if (item is Map)
          ModerationComment(
            id: '${item['id']}',
            firstName: '${item['first_name'] ?? ''}',
            comment: '${item['comment'] ?? ''}',
            overall: item['overall'] is num
                ? (item['overall'] as num).toDouble()
                : 0,
            roomName: '${item['room_name'] ?? ''}',
            venueName: '${item['venue_name'] ?? ''}',
            reports: item['reports'] is num
                ? (item['reports'] as num).round()
                : 0,
            hidden: item['hidden'] == true,
            hiddenReason: '${item['hidden_reason'] ?? ''}',
          ),
    ];
  }

  @override
  Future<void> hide({required String id, required String reason}) {
    return _rpc('admin_hide_review', {
      'p_review_id': id,
      'p_reason': reason.trim(),
    });
  }

  @override
  Future<void> unhide({required String id, required String reason}) {
    return _rpc('admin_unhide_review', {
      'p_review_id': id,
      'p_reason': reason.trim(),
    });
  }

  @override
  Future<List<ModerationEvent>> audit() async {
    final raw = await _rpc('admin_review_audit');
    if (raw is! List) return const [];
    return [
      for (final item in raw)
        if (item is Map)
          ModerationEvent(
            action: '${item['action'] ?? ''}',
            reason: '${item['reason'] ?? ''}',
            reviewId: '${item['review_id'] ?? ''}',
          ),
    ];
  }

  ReviewSettings _settings(Object? raw) {
    final map = raw is Map ? raw : const {};
    return ReviewSettings(
      enabled: map['enabled'] == true,
      priorWeight: map['bayesian_m'] is num
          ? (map['bayesian_m'] as num).round()
          : 10,
      rankingMinimum: map['ranking_min'] is num
          ? (map['ranking_min'] as num).round()
          : 10,
    );
  }

  Future<Object?> _rpc(String fn, [Map<String, Object?>? params]) async {
    try {
      return await client.rpc(fn, params: params);
    } on PostgrestException catch (error) {
      throw AdminRejected(error.message);
    }
  }
}

final reviewAdminProvider = Provider<ReviewAdminApi>((ref) {
  if (!scapeUsesLiveBackend) {
    throw StateError('O Admin real ainda não ligou o Supabase.');
  }
  return SupabaseReviewAdminApi(scapeSupabase);
});

class AvaliacoesPage extends ConsumerStatefulWidget {
  const AvaliacoesPage({super.key});

  @override
  ConsumerState<AvaliacoesPage> createState() => _AvaliacoesPageState();
}

class _AvaliacoesPageState extends ConsumerState<AvaliacoesPage> {
  ReviewSettings? _settings;
  List<ModerationComment> _queue = const [];
  List<ModerationEvent> _audit = const [];
  final _prior = TextEditingController(text: '10');
  final _minimum = TextEditingController(text: '10');
  final _reasons = <String, TextEditingController>{};
  String? _error;
  var _enabled = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _prior.dispose();
    _minimum.dispose();
    for (final controller in _reasons.values) {
      controller.dispose();
    }
    super.dispose();
  }

  TextEditingController _reasonFor(String id) {
    return _reasons.putIfAbsent(id, TextEditingController.new);
  }

  Future<void> _load() async {
    try {
      final api = ref.read(reviewAdminProvider);
      final settings = await api.settings();
      final queue = await api.queue();
      final audit = await api.audit();
      if (!mounted) return;
      _prior.text = '${settings.priorWeight}';
      _minimum.text = '${settings.rankingMinimum}';
      setState(() {
        _settings = settings;
        _enabled = settings.enabled;
        _queue = queue;
        _audit = audit;
        _error = null;
      });
    } on Object catch (error) {
      if (!mounted) return;
      setState(() => _error = '$error');
    }
  }

  Future<void> _save() async {
    final prior = int.tryParse(_prior.text.trim());
    final minimum = int.tryParse(_minimum.text.trim());
    if (prior == null || minimum == null) {
      setState(() => _error = 'm e o mínimo são números inteiros.');
      return;
    }
    try {
      await ref.read(reviewAdminProvider).save(
        ReviewSettings(
          enabled: _enabled,
          priorWeight: prior,
          rankingMinimum: minimum,
        ),
      );
      await _load();
    } on AdminRejected catch (error) {
      if (!mounted) return;
      setState(() => _error = error.message);
    }
  }

  Future<void> _hide(ModerationComment comment) async {
    final reason = _reasonFor(comment.id).text;
    try {
      final api = ref.read(reviewAdminProvider);
      if (comment.hidden) {
        await api.unhide(id: comment.id, reason: reason);
      } else {
        await api.hide(id: comment.id, reason: reason);
      }
      await _load();
    } on AdminRejected catch (error) {
      if (!mounted) return;
      setState(() => _error = error.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = _settings;
    return AdminFrame(
      key: const Key('admin-avaliacoes'),
      title: 'Avaliações',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (settings == null && _error == null)
            const Text('Carregando avaliações…'),
          SwitchListTile(
            key: const Key('admin-avaliacoes-flag'),
            contentPadding: EdgeInsets.zero,
            title: const Text('Avaliações de salas'),
            subtitle: Text(
              _enabled
                  ? 'Ligada. Jogadores podem avaliar sessões pagas e concluídas.'
                  : 'Desligada. Ninguém avalia, o Parceiro não mostra nota e o site não publica AggregateRating.',
            ),
            value: _enabled,
            onChanged: settings == null
                ? null
                : (value) => setState(() => _enabled = value),
          ),
          const SizedBox(height: 8),
          TextField(
            key: const Key('admin-avaliacoes-m'),
            controller: _prior,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: const InputDecoration(
              labelText: 'Peso do prior (m)',
              helperText: 'A média global pesa como m avaliações. Padrão 10.',
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            key: const Key('admin-avaliacoes-minimo'),
            controller: _minimum,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: const InputDecoration(
              labelText: 'Mínimo para o ranking',
              helperText:
                  'Salas e casas entram no ranking e no JSON-LD a partir deste número. Padrão 10.',
            ),
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton(
              key: const Key('admin-avaliacoes-salvar'),
              onPressed: settings == null ? null : _save,
              child: const Text('Salvar'),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!, key: const Key('admin-avaliacoes-erro')),
          ],
          const SizedBox(height: 24),
          Text(
            'Moderação',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          if (_queue.isEmpty) const Text('Nenhum comentário para moderar.'),
          for (final comment in _queue)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${comment.firstName} · ${comment.venueName} · ${comment.roomName}',
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 4),
                    Text(comment.comment),
                    const SizedBox(height: 4),
                    Text(
                      'Nota geral ${comment.overall.toStringAsFixed(1).replaceAll('.', ',')} · ${comment.reports} denúncia(s)'
                      '${comment.hidden ? ' · oculto: ${comment.hiddenReason}' : ''}',
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      key: Key('admin-motivo-${comment.id}'),
                      controller: _reasonFor(comment.id),
                      decoration: const InputDecoration(
                        labelText: 'Motivo',
                      ),
                      maxLength: 280,
                    ),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: OutlinedButton(
                        key: Key('admin-ocultar-${comment.id}'),
                        onPressed: () => _hide(comment),
                        child: Text(comment.hidden ? 'Reexibir' : 'Ocultar'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 16),
          Text(
            'Auditoria',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          if (_audit.isEmpty)
            const Text('Nenhuma alteração nesta sessão.')
          else
            for (final event in _audit)
              Text('${event.action} · ${event.reviewId} · ${event.reason}'),
        ],
      ),
    );
  }
}
