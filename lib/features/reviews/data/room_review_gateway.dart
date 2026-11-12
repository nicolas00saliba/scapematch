import 'package:dominio/dominio.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Envio da avaliação. O banco decide se a pessoa pode avaliar.
abstract class RoomReviewGateway {
  Future<String?> submit({
    required String groupId,
    required ReviewScores scores,
    required String comment,
  });

  Future<String?> report({required String reviewId, required String reason});
}

class MemoryRoomReviewGateway implements RoomReviewGateway {
  final submitted = <String, ReviewScores>{};
  final reports = <String, String>{};

  @override
  Future<String?> submit({
    required String groupId,
    required ReviewScores scores,
    required String comment,
  }) async {
    if (submitted.containsKey(groupId)) {
      return 'Você já avaliou esta sessão.';
    }
    if (reviewCommentTooLong(comment) || !scores.complete) {
      return 'Não foi possível avaliar.';
    }
    submitted[groupId] = scores;
    return null;
  }

  @override
  Future<String?> report({
    required String reviewId,
    required String reason,
  }) async {
    final text = normalizeReviewComment(reason);
    if (text.isEmpty || text.length > reviewCommentLimit) {
      return 'A denúncia fica entre 1 e 280 caracteres.';
    }
    if (reports.containsKey(reviewId)) {
      return 'Você já denunciou este comentário.';
    }
    reports[reviewId] = text;
    return null;
  }
}

class SupabaseRoomReviewGateway implements RoomReviewGateway {
  SupabaseRoomReviewGateway(this.client);

  final SupabaseClient client;

  @override
  Future<String?> submit({
    required String groupId,
    required ReviewScores scores,
    required String comment,
  }) {
    return _call('submit_room_review', {
      'p_group_id': groupId,
      'p_story': scores.story,
      'p_puzzles': scores.puzzles,
      'p_immersion': scores.immersion,
      'p_service': scores.service,
      'p_comfort': scores.comfort,
      'p_value': scores.value,
      'p_comment': normalizeReviewComment(comment),
    });
  }

  @override
  Future<String?> report({required String reviewId, required String reason}) {
    return _call('report_room_review', {
      'p_review_id': reviewId,
      'p_reason': normalizeReviewComment(reason),
    });
  }

  Future<String?> _call(String fn, Map<String, Object?> params) async {
    try {
      await client.rpc(fn, params: params);
      return null;
    } on PostgrestException catch (error) {
      final message = error.message.trim();
      if (message.isEmpty) return 'Não foi possível avaliar.';
      return message;
    }
  }
}
