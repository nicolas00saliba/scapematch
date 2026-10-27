import 'package:flutter_test/flutter_test.dart';
import 'package:scapematch/core/data/fake_database.dart';
import 'package:scapematch/core/data/sample_data.dart';
import 'package:scapematch/core/data/sample_ids.dart';
import 'package:scapematch/features/catalog/data/fake_catalog_repository.dart';
import 'package:scapematch/features/cities/data/fake_city_repository.dart';
import 'package:scapematch/features/groups/data/fake_group_repository.dart';
import 'package:scapematch/features/groups/domain/create_group_request.dart';
import 'package:scapematch/features/groups/domain/group_outcomes.dart';
import 'package:scapematch/features/groups/domain/group_rules.dart';

void main() {
  late FakeDatabase database;
  late FakeGroupRepository groups;
  late FakeCatalogRepository catalog;
  late FakeCityRepository cities;

  setUp(() {
    database = buildSampleDatabase();
    groups = FakeGroupRepository(database, latency: Duration.zero);
    catalog = FakeCatalogRepository(database, latency: Duration.zero);
    cities = FakeCityRepository(database, latency: Duration.zero);
  });

  test('sample data covers the five cities with different houses', () async {
    final listed = await cities.listCities();
    expect(
      listed.map((city) => city.name),
      containsAll([
        'Belo Horizonte',
        'Curitiba',
        'Porto Alegre',
        'Rio de Janeiro',
        'São Paulo',
      ]),
    );

    final houseNamesByCity = <String, Set<String>>{};
    for (final cityId in SampleIds.cities) {
      final houses = await catalog.listHousesByCity(cityId);
      expect(houses, isNotEmpty, reason: cityId);
      expect(houses.every((house) => house.cityId == cityId), isTrue);
      houseNamesByCity[cityId] = houses.map((house) => house.name).toSet();

      final cityGroups = await groups.listByCity(cityId);
      expect(cityGroups, hasLength(2), reason: cityId);
      expect(cityGroups.every((group) => group.cityId == cityId), isTrue);

      final almostFull = await groups.listByCity(cityId, almostFullOnly: true);
      expect(almostFull, isNotEmpty, reason: cityId);
      expect(almostFull.every((group) => group.isAlmostFull), isTrue);
    }

    final signatures = houseNamesByCity.values.map((names) => names.join('|'));
    expect(signatures.toSet(), hasLength(SampleIds.cities.length));
  });

  test('sample groups stay within the room and match their participants', () {
    for (final group in database.groups) {
      expect(group.filledSpots, greaterThan(0));
      expect(group.filledSpots, lessThanOrEqualTo(group.totalSpots));
      expect(group.totalSpots, lessThanOrEqualTo(group.roomCapacity));
      expect(group.participants, hasLength(group.filledSpots));
      expect(group.participants.first.isCreator, isTrue);
      expect(group.joinedByMe, isFalse);
    }
  });

  test('filters groups by the chosen city', () async {
    final saoPaulo = await groups.listByCity(SampleIds.saoPaulo);
    final curitiba = await groups.listByCity(SampleIds.curitiba);

    expect(
      saoPaulo.map((group) => group.roomId),
      contains(SampleIds.roomSpMetro),
    );
    expect(
      saoPaulo.map((group) => group.roomId),
      isNot(contains(SampleIds.roomCwbCofre)),
    );
    expect(
      curitiba.map((group) => group.roomId),
      contains(SampleIds.roomCwbCofre),
    );
    expect(
      saoPaulo
          .map((group) => group.id)
          .toSet()
          .intersection(curitiba.map((group) => group.id).toSet()),
      isEmpty,
    );
  });

  test('Quase cheios keeps only groups missing one or two seats', () async {
    final all = await groups.listByCity(SampleIds.saoPaulo);
    final almost = await groups.listByCity(
      SampleIds.saoPaulo,
      almostFullOnly: true,
    );

    expect(all, hasLength(2));
    expect(almost, hasLength(1));
    expect(almost.single.id, SampleIds.groupSpMetroAlmost);
    expect(almost.single.openSeats, inInclusiveRange(1, 2));
    expect(
      all.map((group) => group.id),
      contains(SampleIds.groupSpCoberturaOpen),
    );
    expect(
      almost.map((group) => group.id),
      isNot(contains(SampleIds.groupSpCoberturaOpen)),
    );
  });

  test('each city leaves several free times on every room', () async {
    for (final cityId in SampleIds.cities) {
      final cityGroups = await groups.listByCity(cityId);
      final almost = cityGroups.where((group) => group.isAlmostFull);
      final open = cityGroups.where(
        (group) => !group.isAlmostFull && !group.isFull,
      );
      expect(almost, hasLength(1), reason: cityId);
      expect(open, hasLength(1), reason: cityId);
      expect(
        open.single.openSeats,
        greaterThan(GroupRules.almostFullMaxOpenSeats),
        reason: cityId,
      );
      expect(
        cityGroups.map((group) => group.roomId).toSet(),
        hasLength(2),
        reason: cityId,
      );

      final houses = await catalog.listHousesByCity(cityId);
      for (final house in houses) {
        final rooms = await catalog.listRoomsByHouse(house.id);
        expect(rooms, isNotEmpty, reason: house.name);
        for (final room in rooms) {
          final slots = await catalog.listSlotsByRoom(room.id);
          final taken = cityGroups
              .where((group) => group.roomId == room.id)
              .map((group) => group.startsAt)
              .toSet();
          final free = slots.where((slot) => !taken.contains(slot.startsAt));
          expect(slots.length, greaterThanOrEqualTo(4), reason: room.name);
          expect(free.length, greaterThanOrEqualTo(3), reason: room.name);
        }
      }
    }

    final sessions = [
      for (final group in database.groups)
        '${group.roomId}|${group.startsAt.toIso8601String()}',
    ];
    expect(sessions.toSet(), hasLength(database.groups.length));
  });

  test('does not join a full group', () async {
    final index = database.groups.indexWhere(
      (group) => group.id == SampleIds.groupSpMetroAlmost,
    );
    final current = database.groups[index];
    database.groups[index] = current.copyWith(filledSpots: current.totalSpots);
    final before = database.groups[index];

    final result = await groups.join(
      SampleIds.groupSpMetroAlmost,
      participantUserId: 'user-local',
      participantName: 'Você',
    );

    expect(result, isA<JoinFailure>());
    expect((result as JoinFailure).reason, JoinFailureReason.full);
    final after = await groups.getById(SampleIds.groupSpMetroAlmost);
    expect(after!.filledSpots, before.filledSpots);
    expect(after.isFull, isTrue);
    expect(after.participants, hasLength(before.participants.length));
  });

  test('join fills the last seat and then refuses another entry', () async {
    final result = await groups.join(
      SampleIds.groupSpMetroAlmost,
      participantUserId: 'user-local',
      participantName: 'Você',
    );

    expect(result, isA<JoinSuccess>());
    final joined = (result as JoinSuccess).group;
    expect(joined.filledSpots, 6);
    expect(joined.isFull, isTrue);
    expect(joined.joinedByMe, isTrue);
    expect(joined.participants.last.displayName, 'Você');

    final second = await groups.join(
      SampleIds.groupSpMetroAlmost,
      participantUserId: 'user-local',
      participantName: 'Você',
    );
    expect(second, isA<JoinFailure>());
    expect((second as JoinFailure).reason, JoinFailureReason.alreadyJoined);
    final stored = await groups.getById(SampleIds.groupSpMetroAlmost);
    expect(stored!.filledSpots, 6);
  });

  test('create rejects a group larger than the room', () async {
    final before = database.groups.length;
    final result = await groups.create(
      _request(
        cityId: SampleIds.portoAlegre,
        houseId: SampleIds.housePoaRedencao,
        roomId: SampleIds.roomPoaEstufa,
        slotId: SampleIds.slotPoaEstufaFree,
        extraSpots: 4,
      ),
    );

    expect(result, isA<CreateGroupFailure>());
    expect(
      (result as CreateGroupFailure).reason,
      CreateGroupFailureReason.exceedsRoomCapacity,
    );
    expect(database.groups, hasLength(before));
  });

  test(
    'create accepts a group that fits, with the creator already seated',
    () async {
      final before = database.groups.length;
      final result = await groups.create(
        _request(
          cityId: SampleIds.portoAlegre,
          houseId: SampleIds.housePoaRedencao,
          roomId: SampleIds.roomPoaEstufa,
          slotId: SampleIds.slotPoaEstufaFree,
          extraSpots: 3,
          creatorDisplayName: 'Ana Teste',
        ),
      );

      expect(result, isA<CreateGroupSuccess>());
      final group = (result as CreateGroupSuccess).group;
      expect(group.cityId, SampleIds.portoAlegre);
      expect(group.roomId, SampleIds.roomPoaEstufa);
      expect(group.filledSpots, 1);
      expect(group.totalSpots, 4);
      expect(group.roomCapacity, 4);
      expect(group.joinedByMe, isTrue);
      expect(group.participants.single.displayName, 'Ana Teste');
      expect(group.participants.single.userId, 'user-local');
      expect(group.participants.single.id, startsWith('ptc-local-'));
      expect(database.groups, hasLength(before + 1));

      final listed = await groups.listByCity(SampleIds.portoAlegre);
      expect(listed.map((item) => item.id), contains(group.id));
    },
  );

  test('create rejects a group that repeats a room and start time', () async {
    final before = database.groups.length;
    final result = await groups.create(
      _request(
        cityId: SampleIds.portoAlegre,
        houseId: SampleIds.housePoaRedencao,
        roomId: SampleIds.roomPoaEstufa,
        slotId: SampleIds.slotPoaEstufaTaken,
        extraSpots: 2,
      ),
    );

    expect(result, isA<CreateGroupFailure>());
    expect(
      (result as CreateGroupFailure).reason,
      CreateGroupFailureReason.duplicateSession,
    );
    expect(database.groups, hasLength(before));
  });

  test('a second create on a newly used slot is rejected', () async {
    final first = await groups.create(
      _request(
        cityId: SampleIds.portoAlegre,
        houseId: SampleIds.housePoaRedencao,
        roomId: SampleIds.roomPoaEstufa,
        slotId: SampleIds.slotPoaEstufaFree,
        extraSpots: 2,
      ),
    );
    expect(first, isA<CreateGroupSuccess>());

    final second = await groups.create(
      _request(
        cityId: SampleIds.portoAlegre,
        houseId: SampleIds.housePoaRedencao,
        roomId: SampleIds.roomPoaEstufa,
        slotId: SampleIds.slotPoaEstufaFree,
        extraSpots: 2,
      ),
    );
    expect(second, isA<CreateGroupFailure>());
    expect(
      (second as CreateGroupFailure).reason,
      CreateGroupFailureReason.duplicateSession,
    );
  });

  test('joining two groups mints two participant ids', () async {
    final first = await groups.join(
      SampleIds.groupSpMetroAlmost,
      participantUserId: 'user-local',
      participantName: 'Ana Teste',
    );
    final second = await groups.join(
      SampleIds.groupSpCoberturaOpen,
      participantUserId: 'user-local',
      participantName: 'Ana Teste',
    );

    final joinedFirst = first as JoinSuccess;
    final joinedSecond = second as JoinSuccess;
    final firstId = joinedFirst.group.participants.last.id;
    final secondId = joinedSecond.group.participants.last.id;
    expect(firstId, isNot(secondId));
    expect(joinedFirst.group.participants.last.displayName, 'Ana Teste');
    expect(joinedFirst.group.participants.last.userId, 'user-local');

    final everyId = [
      for (final group in database.groups)
        for (final person in group.participants) person.id,
    ];
    expect(everyId.toSet(), hasLength(everyId.length));
  });
}

CreateGroupRequest _request({
  required String cityId,
  required String houseId,
  required String roomId,
  required String slotId,
  required int extraSpots,
  String creatorUserId = 'user-local',
  String creatorDisplayName = 'Você',
}) {
  return CreateGroupRequest(
    cityId: cityId,
    houseId: houseId,
    roomId: roomId,
    slotId: slotId,
    extraSpots: extraSpots,
    creatorUserId: creatorUserId,
    creatorDisplayName: creatorDisplayName,
  );
}
