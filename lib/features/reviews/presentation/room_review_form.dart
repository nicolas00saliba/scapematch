import 'package:dominio/dominio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scapematch/core/ui/app_keys.dart';
import 'package:scapematch/features/reviews/presentation/review_stars.dart';
import 'package:scapematch/providers/repositories.dart';

/// Uma linha por categoria, cinco botões, um toque. O texto é opcional.
class RoomReviewForm extends StatefulWidget {
  const RoomReviewForm({
    super.key,
    required this.roomName,
    required this.houseName,
    required this.onSubmit,
  });

  final String roomName;
  final String houseName;
  final Future<String?> Function(ReviewScores scores, String comment) onSubmit;

  @override
  State<RoomReviewForm> createState() => _RoomReviewFormState();
}

class _RoomReviewFormState extends State<RoomReviewForm> {
  final _scores = <ReviewCategory, int>{};
  final _comment = TextEditingController();
  var _sending = false;
  String? _error;

  @override
  void dispose() {
    _comment.dispose();
    super.dispose();
  }

  ReviewScores? get _complete {
    if (_scores.length != ReviewCategory.values.length) return null;
    final scores = ReviewScores(
      story: _scores[ReviewCategory.story]!,
      puzzles: _scores[ReviewCategory.puzzles]!,
      immersion: _scores[ReviewCategory.immersion]!,
      service: _scores[ReviewCategory.service]!,
      comfort: _scores[ReviewCategory.comfort]!,
      value: _scores[ReviewCategory.value]!,
    );
    return scores.complete ? scores : null;
  }

  Future<void> _send() async {
    final scores = _complete;
    if (scores == null || _sending) return;
    setState(() {
      _sending = true;
      _error = null;
    });
    final failure = await widget.onSubmit(
      scores,
      normalizeReviewComment(_comment.text),
    );
    if (!mounted) return;
    if (failure != null) {
      setState(() {
        _sending = false;
        _error = failure;
      });
      return;
    }
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop(true);
      return;
    }
    setState(() => _sending = false);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final overall = _complete == null ? null : reviewOverall(_complete!);
    final tooLong = reviewCommentTooLong(_comment.text);
    return ListView(
      key: AppKeys.roomReviewForm,
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      children: [
        Text(
          widget.roomName,
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          widget.houseName,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          'Um toque por linha. O comentário é opcional.',
          style: theme.textTheme.bodyMedium,
        ),
        const SizedBox(height: 8),
        Text(
          '1 ${reviewScoreLabels[1]} · 2 ${reviewScoreLabels[2]} · 3 ${reviewScoreLabels[3]} · 4 ${reviewScoreLabels[4]} · 5 ${reviewScoreLabels[5]}',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 16),
        for (final category in ReviewCategory.values) ...[
          Text(
            reviewCategoryLabels[category]!,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              for (var score = 1; score <= 5; score++)
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(right: score == 5 ? 0 : 6),
                    child: _ScoreButton(
                      category: category,
                      score: score,
                      selected: _scores[category] == score,
                      onTap: () => setState(() => _scores[category] = score),
                    ),
                  ),
                ),
            ],
          ),
          if (_scores[category] != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                reviewScoreLabels[_scores[category]]!,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          const SizedBox(height: 14),
        ],
        TextField(
          key: AppKeys.roomReviewComment,
          controller: _comment,
          minLines: 2,
          maxLines: 4,
          maxLength: reviewCommentLimit,
          decoration: const InputDecoration(
            labelText: 'Comentário (opcional)',
            alignLabelWithHint: true,
          ),
          onChanged: (_) => setState(() {}),
        ),
        if (tooLong)
          const Text('O comentário passa de 280 caracteres.'),
        if (overall != null) ...[
          const SizedBox(height: 8),
          const Text('Nota geral'),
          const SizedBox(height: 4),
          ReviewOverallLine(
            average: overall,
            starKey: AppKeys.roomReviewOverall,
          ),
        ],
        if (_error != null) ...[
          const SizedBox(height: 12),
          Text(
            _error!,
            key: AppKeys.roomReviewError,
            style: TextStyle(color: theme.colorScheme.error),
          ),
        ],
        const SizedBox(height: 16),
        FilledButton(
          key: AppKeys.roomReviewSubmit,
          onPressed: _complete == null || _sending || tooLong ? null : _send,
          child: Text(_sending ? 'Enviando…' : 'Enviar avaliação'),
        ),
      ],
    );
  }
}

class _ScoreButton extends StatelessWidget {
  const _ScoreButton({
    required this.category,
    required this.score,
    required this.selected,
    required this.onTap,
  });

  final ReviewCategory category;
  final int score;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final label = reviewScoreLabels[score]!;
    final categoryLabel = reviewCategoryLabels[category]!;
    return Semantics(
      button: true,
      selected: selected,
      label: '$categoryLabel, $score, $label',
      child: OutlinedButton(
        key: AppKeys.reviewScore(category.name, score),
        onPressed: onTap,
        style: OutlinedButton.styleFrom(
          backgroundColor: selected
              ? Theme.of(context).colorScheme.primary
              : null,
          foregroundColor: selected
              ? Theme.of(context).colorScheme.onPrimary
              : null,
          padding: const EdgeInsets.symmetric(horizontal: 0, vertical: 12),
          visualDensity: VisualDensity.compact,
        ),
        child: Text(
          '$score',
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
    );
  }
}

Future<bool> showRoomReviewSheet({
  required BuildContext context,
  required WidgetRef ref,
  required String groupId,
  required String roomName,
  required String houseName,
}) async {
  final gateway = ref.read(roomReviewGatewayProvider);
  final sent = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) {
      return FractionallySizedBox(
        heightFactor: 0.92,
        child: RoomReviewForm(
          roomName: roomName,
          houseName: houseName,
          onSubmit: (scores, comment) => gateway.submit(
            groupId: groupId,
            scores: scores,
            comment: comment,
          ),
        ),
      );
    },
  );
  return sent ?? false;
}
