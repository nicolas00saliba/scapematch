import 'dart:async';

import 'package:dominio/dominio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scapematch/core/supabase/scape_backend.dart';
import 'package:scapematch/features/reviews/presentation/review_stars.dart';
import 'package:scapematch/providers/repositories.dart';
import 'package:scapematch_parceiro/features/partner/presentation/partner_session.dart';
import 'package:scapematch_parceiro/partner_keys.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Painel da casa. Só agregados e o primeiro nome no comentário.
class PartnerReviewsSection extends ConsumerWidget {
  const PartnerReviewsSection({super.key, required this.houseName});

  final String houseName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final enabled = ref.watch(reviewsEnabledProvider);
    return enabled.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, stackTrace) => const Center(
        child: Text('Não foi possível carregar as avaliações.'),
      ),
      data: (on) {
        if (!on || !scapeUsesLiveBackend) {
          return const PartnerReviewsOff();
        }
        final houseId = ref.watch(partnerSessionProvider)?.houseId ?? '';
        if (houseId.isEmpty) return const PartnerReviewsOff();
        return PartnerReviewsLive(houseId: houseId, houseName: houseName);
      },
    );
  }
}

class PartnerReviewsOff extends StatelessWidget {
  const PartnerReviewsOff({super.key});

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(24),
        child: Text(
          'As avaliações estão desligadas. Quando o Admin ligar, a nota por categoria, a evolução e os comentários desta casa aparecem aqui.',
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}

class PartnerReviewsLive extends ConsumerStatefulWidget {
  const PartnerReviewsLive({
    super.key,
    required this.houseId,
    required this.houseName,
  });

  final String houseId;
  final String houseName;

  @override
  ConsumerState<PartnerReviewsLive> createState() => _PartnerReviewsLiveState();
}

class _PartnerReviewsLiveState extends ConsumerState<PartnerReviewsLive> {
  VenueReviewBoard? _board;
  String? _error;
  RealtimeChannel? _channel;

  @override
  void initState() {
    super.initState();
    _load();
    _listen();
  }

  @override
  void dispose() {
    final channel = _channel;
    if (channel != null) {
      scapeSupabase.removeChannel(channel);
    }
    super.dispose();
  }

  void _listen() {
    final channel = scapeSupabase.channel('reviews-${widget.houseId}');
    channel.onPostgresChanges(
      event: PostgresChangeEvent.all,
      schema: 'public',
      table: 'room_rating_rollups',
      filter: PostgresChangeFilter(
        type: PostgresChangeFilterType.eq,
        column: 'venue_id',
        value: widget.houseId,
      ),
      callback: (payload) {
        unawaited(_load());
      },
    );
    channel.subscribe();
    _channel = channel;
  }

  Future<void> _load() async {
    try {
      final raw = await scapeSupabase.rpc(
        'venue_review_insights',
        params: {'p_venue_id': widget.houseId},
      );
      if (!mounted) return;
      final data = raw is Map<String, dynamic>
          ? raw
          : Map<String, dynamic>.from(raw as Map);
      if (data['enabled'] != true) {
        setState(() {
          _board = null;
          _error = null;
        });
        return;
      }
      setState(() {
        _board = venueReviewBoardFromJson(data, houseName: widget.houseName);
        _error = null;
      });
    } on Object catch (error) {
      if (!mounted) return;
      setState(() => _error = '$error');
    }
  }

  Future<String?> _reply(String reviewId, String body) async {
    try {
      await scapeSupabase.rpc(
        'reply_room_review',
        params: {'p_review_id': reviewId, 'p_body': body},
      );
      await _load();
      return null;
    } on PostgrestException catch (error) {
      return error.message;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return Center(child: Text(_error!));
    }
    final board = _board;
    if (board == null) {
      return const Center(child: CircularProgressIndicator());
    }
    return PartnerReviewsPanel(board: board, onReply: _reply);
  }
}

class PartnerReviewsPanel extends StatelessWidget {
  const PartnerReviewsPanel({
    super.key,
    required this.board,
    required this.onReply,
  });

  final VenueReviewBoard board;
  final Future<String?> Function(String reviewId, String body) onReply;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      key: PartnerKeys.partnerReviews,
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
      children: [
        Text(
          'Avaliações',
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w800,
          ),
        ),
        Text(board.houseName),
        const SizedBox(height: 12),
        if (board.count == 0)
          const Text('Ainda não há avaliações desta casa.')
        else ...[
          ReviewOverallLine(average: board.overall, count: board.count),
          const SizedBox(height: 20),
          Text(
            'Por categoria',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          for (final category in ReviewCategory.values)
            _CategoryRow(
              label: reviewCategoryLabels[category]!,
              venue: board.categories[category] ?? 0,
              city: board.cityCategories[category] ?? 0,
            ),
          const SizedBox(height: 20),
          Text(
            'Por sala',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          for (final room in board.rooms)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(room.name),
              subtitle: ReviewStars(average: room.average, size: 18),
              trailing: Text(
                '${room.average.toStringAsFixed(1).replaceAll('.', ',')} · ${room.count}',
              ),
            ),
          const SizedBox(height: 12),
          Text(
            'Evolução',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          for (final month in board.months) _MonthBar(month: month),
          const SizedBox(height: 20),
          Text(
            'Distribuição',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          _Distribution(counts: board.distribution, total: board.count),
          const SizedBox(height: 20),
          Text(
            'Comentários',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          if (board.comments.isEmpty)
            const Text('Nenhum comentário visível.')
          else
            for (final comment in board.comments)
              _CommentCard(comment: comment, onReply: onReply),
        ],
      ],
    );
  }
}

class _CategoryRow extends StatelessWidget {
  const _CategoryRow({
    required this.label,
    required this.venue,
    required this.city,
  });

  final String label;
  final double venue;
  final double city;

  @override
  Widget build(BuildContext context) {
    final standing = standingOf(venue: venue, city: city);
    final note = switch (standing) {
      CategoryStanding.strength => 'acima da cidade',
      CategoryStanding.weakness => 'abaixo da cidade',
      CategoryStanding.even => 'na média da cidade',
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Expanded(flex: 3, child: Text(label)),
          Expanded(
            flex: 2,
            child: Text(venue.toStringAsFixed(1).replaceAll('.', ',')),
          ),
          Expanded(
            flex: 3,
            child: Text(
              note,
              key: Key('review-standing-$label'),
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}

class _MonthBar extends StatelessWidget {
  const _MonthBar({required this.month});

  final ReviewMonth month;

  @override
  Widget build(BuildContext context) {
    final width = (month.average / 5).clamp(0, 1).toDouble();
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          SizedBox(width: 72, child: Text(month.month)),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(value: width, minHeight: 10),
            ),
          ),
          const SizedBox(width: 8),
          Text(month.average.toStringAsFixed(1).replaceAll('.', ',')),
        ],
      ),
    );
  }
}

class _Distribution extends StatelessWidget {
  const _Distribution({required this.counts, required this.total});

  final Map<int, int> counts;
  final int total;

  @override
  Widget build(BuildContext context) {
    final peak = [
      for (var score = 1; score <= 5; score++) counts[score] ?? 0,
    ].fold<int>(1, (max, value) => value > max ? value : max);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        for (var score = 1; score <= 5; score++)
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Column(
                children: [
                  Text('${counts[score] ?? 0}'),
                  const SizedBox(height: 4),
                  SizedBox(
                    height: 80,
                    child: Align(
                      alignment: Alignment.bottomCenter,
                      child: FractionallySizedBox(
                        heightFactor: ((counts[score] ?? 0) / peak).clamp(
                          0.04,
                          1,
                        ),
                        widthFactor: 1,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.primary,
                            borderRadius: BorderRadius.circular(6),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text('$score'),
                  Text(
                    reviewScoreLabels[score]!,
                    style: Theme.of(context).textTheme.bodySmall,
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _CommentCard extends StatefulWidget {
  const _CommentCard({required this.comment, required this.onReply});

  final PublicReviewComment comment;
  final Future<String?> Function(String reviewId, String body) onReply;

  @override
  State<_CommentCard> createState() => _CommentCardState();
}

class _CommentCardState extends State<_CommentCard> {
  final _reply = TextEditingController();
  String? _error;
  var _sending = false;

  @override
  void dispose() {
    _reply.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = normalizeReviewComment(_reply.text);
    if (text.isEmpty || _sending) return;
    setState(() {
      _sending = true;
      _error = null;
    });
    final failure = await widget.onReply(widget.comment.id, text);
    if (!mounted) return;
    setState(() {
      _sending = false;
      _error = failure;
      if (failure == null) _reply.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final comment = widget.comment;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              comment.firstName,
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 4),
            ReviewStars(average: comment.overall, size: 16),
            const SizedBox(height: 8),
            Text(comment.body),
            if (comment.reply != null) ...[
              const SizedBox(height: 8),
              Text('Resposta da casa: ${comment.reply}'),
            ] else ...[
              const SizedBox(height: 8),
              TextField(
                key: PartnerKeys.partnerReviewReply,
                controller: _reply,
                decoration: const InputDecoration(
                  labelText: 'Responder',
                ),
                maxLength: reviewCommentLimit,
              ),
              Align(
                alignment: Alignment.centerLeft,
                child: FilledButton(
                  onPressed: _sending ? null : _send,
                  child: const Text('Publicar resposta'),
                ),
              ),
            ],
            if (_error != null) Text(_error!),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: () => _report(context),
                child: const Text('Denunciar'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _report(BuildContext context) async {
    final reason = TextEditingController();
    final sent = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Denunciar comentário'),
          content: TextField(
            controller: reason,
            decoration: const InputDecoration(
              labelText: 'Motivo',
            ),
            maxLength: reviewCommentLimit,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Enviar'),
            ),
          ],
        );
      },
    );
    final text = normalizeReviewComment(reason.text);
    reason.dispose();
    if (sent != true || text.isEmpty || !context.mounted) return;
    try {
      await scapeSupabase.rpc(
        'report_room_review',
        params: {'p_review_id': widget.comment.id, 'p_reason': text},
      );
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Denúncia enviada.')),
      );
    } on PostgrestException catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.message)),
      );
    }
  }
}

VenueReviewBoard venueReviewBoardFromJson(
  Map<String, dynamic> json, {
  required String houseName,
}) {
  Map<ReviewCategory, double> readCategories(Object? raw) {
    final map = raw is Map ? raw : const {};
    return {
      for (final category in ReviewCategory.values)
        category: _asDouble(map[category.name]),
    };
  }

  final rooms = <({String name, double average, int count})>[
    if (json['rooms'] is List)
      for (final item in json['rooms'] as List)
        if (item is Map)
          (
            name: '${item['name'] ?? ''}',
            average: _asDouble(item['average']),
            count: _asInt(item['count']),
          ),
  ];
  final months = <ReviewMonth>[
    if (json['months'] is List)
      for (final item in json['months'] as List)
        if (item is Map)
          ReviewMonth(
            month: '${item['month'] ?? ''}',
            count: _asInt(item['count']),
            average: _asDouble(item['average']),
          ),
  ];
  final distribution = <int, int>{
    for (var score = 1; score <= 5; score++)
      score: json['distribution'] is Map
          ? _asInt((json['distribution'] as Map)['$score'])
          : 0,
  };
  final comments = <PublicReviewComment>[
    if (json['comments'] is List)
      for (final item in json['comments'] as List)
        if (item is Map)
          PublicReviewComment(
            id: '${item['id'] ?? ''}',
            firstName: '${item['first_name'] ?? ''}',
            body: '${item['comment'] ?? ''}',
            overall: _asDouble(item['overall']),
            reply: item['reply'] == null ? null : '${item['reply']}',
          ),
  ];
  return VenueReviewBoard(
    houseName: houseName,
    overall: _asDouble(json['overall']),
    count: _asInt(json['review_count']),
    categories: readCategories(json['categories']),
    cityCategories: readCategories(json['city_categories']),
    rooms: rooms,
    months: months,
    distribution: distribution,
    comments: comments,
  );
}

double _asDouble(Object? value) {
  if (value is num) return value.toDouble();
  return double.tryParse('${value ?? ''}') ?? 0;
}

int _asInt(Object? value) {
  if (value is int) return value;
  if (value is num) return value.round();
  return int.tryParse('${value ?? ''}') ?? 0;
}
