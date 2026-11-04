import 'package:flutter_test/flutter_test.dart';
import 'package:scapematch/features/community/domain/community_board.dart';
import 'package:scapematch/features/groups/data/fake_group_repository.dart';
import 'package:scapematch/features/groups/domain/create_group_request.dart';
import 'package:scapematch/features/groups/domain/group_outcomes.dart';
import 'package:scapematch/features/groups/domain/party_companion.dart';
import 'package:scapematch/features/social/data/memory_social_repository.dart';
import 'package:scapematch/features/social/data/sample_players.dart';
import 'package:scapematch/features/social/data/supabase_social_repository.dart';

import 'support/sample_clock.dart';

void main() {
  test('entrar com a turma não estoura as vagas', () async {
    final clock = loadSampleClock();
    final database = loadSampleDatabase();
    final board = CommunityBoard();
    final social = MemorySocialRepository(board: board, clock: clock);
    final groups = FakeGroupRepository(
      database,
      clock: clock,
      latency: Duration.zero,
      board: board,
      friends: social,
    );
    final party = social.companionsForCrew(
      actorId: sampleLocalUserId,
      crewId: sampleCrewId,
    );
    expect(party, hasLength(2));

    const tightId = 'grp-cwb-cofre-almost';
    final tightBefore = (await groups.getById(tightId))!;
    expect(tightBefore.openSeats, lessThan(3));
    final tightSeats = [
      for (final person in tightBefore.participants) person.id,
    ];
    final denied = await groups.joinParty(
      tightId,
      leaderUserId: sampleLocalUserId,
      leaderName: 'Nícolas',
      companions: party,
    );
    expect(denied, isA<JoinFailure>());
    expect((denied as JoinFailure).reason, JoinFailureReason.partyDoesNotFit);
    final tightAfter = (await groups.getById(tightId))!;
    expect(tightAfter.filledSpots, tightBefore.filledSpots);
    expect([
      for (final person in tightAfter.participants) person.id,
    ], tightSeats);
    expect(tightAfter.participantForUser(sampleLocalUserId), isNull);

    const openId = 'grp-cwb-opera-open';
    final openBefore = (await groups.getById(openId))!;
    expect(openBefore.openSeats, greaterThanOrEqualTo(3));
    final notFriend = await groups.joinParty(
      openId,
      leaderUserId: sampleLocalUserId,
      leaderName: 'Nícolas',
      companions: const [
        PartyCompanion(userId: 'user-lia', displayName: 'Lia'),
      ],
    );
    expect(
      (notFriend as JoinFailure).reason,
      JoinFailureReason.companionNotFriend,
    );
    expect((await groups.getById(openId))!.filledSpots, openBefore.filledSpots);

    final joined = await groups.joinParty(
      openId,
      leaderUserId: sampleLocalUserId,
      leaderName: 'Nícolas',
      companions: party,
    );
    expect(joined, isA<JoinSuccess>());
    final seated = (joined as JoinSuccess).group;
    expect(seated.filledSpots, openBefore.filledSpots + party.length + 1);
    expect(seated.filledSpots, lessThanOrEqualTo(seated.totalSpots));
    expect(seated.openSeats, openBefore.openSeats - 3);
    expect(seated.participantForUser(sampleLocalUserId)?.occupiesSeat, isTrue);
    expect(seated.participantForUser(sampleCrewMateLuna)?.occupiesSeat, isTrue);
    expect(seated.participantForUser(sampleCrewMateEnzo)?.occupiesSeat, isTrue);

    final overflow = await groups.joinParty(
      openId,
      leaderUserId: 'user-marina',
      leaderName: 'Marina',
      companions: const [
        PartyCompanion(userId: 'user-caio', displayName: 'Caio'),
        PartyCompanion(userId: 'user-helena', displayName: 'Helena'),
      ],
    );
    expect(overflow, isA<JoinFailure>());
    final still = (await groups.getById(openId))!;
    expect(still.filledSpots, seated.filledSpots);
    expect(still.participantForUser('user-marina'), isNull);
    expect(still.filledSpots, lessThanOrEqualTo(still.totalSpots));
  });

  test('criar com a turma deixa vaga aberta e não grava pela metade', () async {
    final clock = loadSampleClock();
    final database = loadSampleDatabase();
    final social = MemorySocialRepository(
      board: CommunityBoard(),
      clock: clock,
    );
    final groups = FakeGroupRepository(
      database,
      clock: clock,
      latency: Duration.zero,
      friends: social,
    );
    final party = social.companionsForCrew(
      actorId: sampleLocalUserId,
      crewId: sampleCrewId,
    );
    final room = database.roomById('room-cwb-opera')!;
    final house = database.houseById(room.houseId)!;
    final taken = {
      for (final group in database.groups)
        if (!group.isCancelled)
          '${group.roomId}|${group.startsAt.toIso8601String()}',
    };
    final slot = database.slots.firstWhere(
      (item) =>
          item.roomId == room.id &&
          item.startsAt.isAfter(clock.now()) &&
          !taken.contains('${item.roomId}|${item.startsAt.toIso8601String()}'),
    );
    final full = await groups.create(
      CreateGroupRequest(
        cityId: house.cityId,
        houseId: house.id,
        roomId: room.id,
        slotId: slot.id,
        extraSpots: party.length,
        creatorUserId: sampleLocalUserId,
        creatorDisplayName: 'Nícolas',
        companions: party,
      ),
    );
    expect(full, isA<CreateGroupFailure>());
    expect(
      (full as CreateGroupFailure).reason,
      CreateGroupFailureReason.crewLeavesNoOpenSeat,
    );
    expect(database.groups.where((group) => group.slotId == slot.id), isEmpty);

    final created = await groups.create(
      CreateGroupRequest(
        cityId: house.cityId,
        houseId: house.id,
        roomId: room.id,
        slotId: slot.id,
        extraSpots: party.length + 1,
        creatorUserId: sampleLocalUserId,
        creatorDisplayName: 'Nícolas',
        companions: party,
      ),
    );
    expect(created, isA<CreateGroupSuccess>());
    final group = (created as CreateGroupSuccess).group;
    expect(group.filledSpots, 1 + party.length);
    expect(group.totalSpots, group.filledSpots + 1);
    expect(group.openSeats, 1);
    expect(group.participantForUser(sampleCrewMateLuna), isNotNull);
    expect(group.participantForUser(sampleCrewMateEnzo), isNotNull);
  });

  test('o repositório Supabase aponta para as funções do SQL', () async {
    final calls = <String>[];
    Future<dynamic> rpc(String function, Map<String, dynamic> args) async {
      calls.add(function);
      if (function == 'list_my_friends' || function == 'list_my_crews') {
        return const <Map<String, dynamic>>[];
      }
      return 'ok';
    }

    final social = SupabaseSocialRepository(rpc);
    await social.requestByUsername(actorId: 'user-local', username: '@luna');
    await social.acceptFriend(actorId: 'user-local', friendshipId: 'fr');
    await SupabasePartyGateway(rpc).joinWithParty(
      groupId: 'grp',
      companionIds: const ['user-luna', 'user-enzo'],
    );
    expect(calls, [
      'request_friend_by_username',
      'respond_friendship',
      'join_group_with_party',
    ]);
  });
}
