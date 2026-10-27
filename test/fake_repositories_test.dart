import 'package:flutter_test/flutter_test.dart';
import 'package:scapematch/core/data/fake_database.dart';
import 'package:scapematch/core/data/sample_data.dart';
import 'package:scapematch/core/data/sample_ids.dart';
import 'package:scapematch/features/catalog/data/fake_catalog_repository.dart';
import 'package:scapematch/features/cities/data/fake_city_repository.dart';
import 'package:scapematch/features/groups/data/fake_group_repository.dart';
import 'package:scapematch/features/groups/domain/create_group_request.dart';
import 'package:scapematch/features/groups/domain/group_outcomes.dart';

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
      expect(cityGroups, isNotEmpty, reason: cityId);
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

    expect(
      almost.map((group) => group.id),
      contains(SampleIds.groupSpMetroAlmost),
    );
    expect(
      almost.map((group) => group.id),
      contains(SampleIds.groupSpIzakayaAlmost),
    );
    expect(
      almost.map((group) => group.id),
      isNot(contains(SampleIds.groupSpMetroOpen)),
    );
    expect(
      almost.map((group) => group.id),
      isNot(contains(SampleIds.groupSpCoberturaFull)),
    );
    expect(all.length, greaterThan(almost.length));
  });

  test('does not join a full group', () async {
    final before = await groups.getById(SampleIds.groupSpCoberturaFull);
    final result = await groups.join(
      SampleIds.groupSpCoberturaFull,
      participantName: 'Você',
    );

    expect(result, isA<JoinFailure>());
    expect((result as JoinFailure).reason, JoinFailureReason.full);
    final after = await groups.getById(SampleIds.groupSpCoberturaFull);
    expect(after!.filledSpots, before!.filledSpots);
    expect(after.participants, hasLength(before.participants.length));
  });

  test('join fills the last seat and then refuses another entry', () async {
    final result = await groups.join(
      SampleIds.groupSpMetroAlmost,
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
      const CreateGroupRequest(
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
        const CreateGroupRequest(
          cityId: SampleIds.portoAlegre,
          houseId: SampleIds.housePoaRedencao,
          roomId: SampleIds.roomPoaEstufa,
          slotId: SampleIds.slotPoaEstufaFree,
          extraSpots: 3,
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
      expect(database.groups, hasLength(before + 1));

      final listed = await groups.listByCity(SampleIds.portoAlegre);
      expect(listed.map((item) => item.id), contains(group.id));
    },
  );
}
