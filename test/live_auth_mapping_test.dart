import 'package:flutter_test/flutter_test.dart';
import 'package:scapematch/features/auth/data/auth_messages.dart';
import 'package:scapematch/features/groups/data/group_rpc_errors.dart';
import 'package:scapematch/features/groups/domain/group_outcomes.dart';
import 'package:scapematch/features/news/data/supabase_news_repository.dart';
import 'package:scapematch/features/news/domain/news_item.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  test('auth errors stay in Portuguese', () {
    expect(
      authErrorMessage(
        const AuthException('Invalid login credentials'),
        fallback: 'falha',
      ),
      'E-mail ou senha não conferem.',
    );
    expect(
      authErrorMessage(
        const AuthException('User already registered'),
        fallback: 'falha',
      ),
      'Esse e-mail já tem conta. Entre com ele.',
    );
    expect(
      authErrorMessage(Exception('socket'), fallback: 'sem rede'),
      'Sem conexão. Tente de novo.',
    );
  });

  test('group function errors map to the screen reasons', () {
    expect(
      createGroupFailure('below room minimum'),
      CreateGroupFailureReason.belowRoomMinimum,
    );
    expect(
      createGroupFailure('duplicate session'),
      CreateGroupFailureReason.duplicateSession,
    );
    expect(joinFailure('group full'), JoinFailureReason.full);
    expect(joinFailure('offer expired'), JoinFailureReason.offerExpired);
    expect(joinFailure('seat reserved'), JoinFailureReason.seatReserved);
    expect(
      joinFailure('O prazo deste grupo acabou'),
      JoinFailureReason.deadlinePassed,
    );
    expect(
      editFailure('exceeds room capacity'),
      EditGroupFailureReason.exceedsRoomCapacity,
    );
    expect(
      deleteFailure('too close to delete'),
      DeleteGroupFailureReason.tooCloseToDelete,
    );
    expect(waitlistError('already joined'), 'Você já está neste grupo.');
  });

  test('news categories use the database names', () {
    expect(newsCategoryOf('new_room'), NewsCategory.newRoom);
    expect(newsCategoryOf('promotion'), NewsCategory.promotion);
    expect(newsSourceOf('instagram'), NewsSourceKind.instagram);
  });
}
