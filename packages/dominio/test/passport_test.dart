import 'package:dominio/dominio.dart';
import 'package:test/test.dart';

void main() {
  final start = DateTime.utc(2026, 11, 11, 19);

  test('comparecimento só depois da sessão paga', () {
    expect(
      sessionCheckinBlock(
        now: start.subtract(const Duration(minutes: 1)),
        startsAt: start,
        paid: true,
        refunded: false,
        seatCancelled: false,
        groupCancelled: false,
      ),
      'A sessão ainda não começou.',
    );
    expect(
      sessionCheckinBlock(
        now: start,
        startsAt: start,
        paid: true,
        refunded: false,
        seatCancelled: false,
        groupCancelled: false,
      ),
      isNull,
    );
    expect(
      sessionCheckinBlock(
        now: start.add(const Duration(hours: 1)),
        startsAt: start,
        paid: false,
        refunded: false,
        seatCancelled: false,
        groupCancelled: false,
      ),
      'Só confirma quem pagou e não foi estornado.',
    );
    expect(
      sessionCheckinBlock(
        now: start.add(const Duration(hours: 1)),
        startsAt: start,
        paid: true,
        refunded: true,
        seatCancelled: false,
        groupCancelled: false,
      ),
      'Só confirma quem pagou e não foi estornado.',
    );
  });

  const rules = PassportRules.provisional;

  test('os padrões provisórios são 5, 10, 25 e 300 na casa', () {
    expect(rules.countMilestones.map((item) => item.rooms), [5, 10, 25]);
    expect(rules.countMilestones.map((item) => item.points), [500, 1000, 3000]);
    expect(rules.housePoints, 300);
  });

  test('jogar de novo não abre outro carimbo', () {
    expect(
      nextPassportPlayCount(current: null, chargeAlreadyCounted: false),
      1,
    );
    expect(
      nextPassportPlayCount(current: 1, chargeAlreadyCounted: true),
      1,
    );
    expect(
      nextPassportPlayCount(current: 1, chargeAlreadyCounted: false),
      2,
    );
  });

  test('cinco salas pagam 500 e a sexta não duplica', () {
    final stamps = [
      for (var i = 0; i < 5; i++)
        RoomStamp(roomId: 'r$i', venueId: 'v', playCount: i == 0 ? 2 : 1),
    ];
    final first = planPassportMilestones(
      rules: rules,
      stamps: stamps,
      roomsByVenue: const {},
      open: const [],
    );
    expect(first.grant.map((item) => item.key), ['count:5']);
    expect(first.grant.single.points, 500);
    expect(first.reverse, isEmpty);

    final again = planPassportMilestones(
      rules: rules,
      stamps: stamps,
      roomsByVenue: const {},
      open: const [OpenPassportMilestone(key: 'count:5', roomIds: [])],
    );
    expect(again.grant, isEmpty);
    expect(again.reverse, isEmpty);
  });

  test('dez e vinte e cinco salas somam os marcos anteriores', () {
    final plan = planPassportMilestones(
      rules: rules,
      stamps: [
        for (var i = 0; i < 25; i++)
          RoomStamp(roomId: 'r$i', venueId: 'v$i', playCount: 1),
      ],
      roomsByVenue: const {},
      open: const [],
    );
    expect(plan.grant.map((item) => item.points), [500, 1000, 3000]);
  });

  test('cair abaixo do marco estorna só esse marco', () {
    final plan = planPassportMilestones(
      rules: rules,
      stamps: [
        for (var i = 0; i < 7; i++)
          RoomStamp(roomId: 'r$i', venueId: 'v', playCount: 1),
      ],
      roomsByVenue: const {},
      open: const [
        OpenPassportMilestone(key: 'count:5', roomIds: []),
        OpenPassportMilestone(key: 'count:10', roomIds: []),
      ],
    );
    expect(plan.grant, isEmpty);
    expect(plan.reverse, ['count:10']);
  });

  test('casa com uma sala não fecha, e a de duas paga uma vez', () {
    final rooms = {
      'solo': ['s1'],
      'dupla': ['d1', 'd2'],
    };
    final before = planPassportMilestones(
      rules: rules,
      stamps: const [
        RoomStamp(roomId: 's1', venueId: 'solo', playCount: 1),
        RoomStamp(roomId: 'd1', venueId: 'dupla', playCount: 1),
      ],
      roomsByVenue: rooms,
      open: const [],
    );
    expect(before.grant.where((item) => item.key.startsWith('house:')), isEmpty);

    final closed = planPassportMilestones(
      rules: rules,
      stamps: const [
        RoomStamp(roomId: 'd1', venueId: 'dupla', playCount: 1),
        RoomStamp(roomId: 'd2', venueId: 'dupla', playCount: 1),
      ],
      roomsByVenue: rooms,
      open: const [],
    );
    expect(closed.grant.single.key, 'house:dupla');
    expect(closed.grant.single.points, 300);
    expect(closed.grant.single.roomIds, ['d1', 'd2']);

    final kept = planPassportMilestones(
      rules: rules,
      stamps: const [
        RoomStamp(roomId: 'd1', venueId: 'dupla', playCount: 1),
        RoomStamp(roomId: 'd2', venueId: 'dupla', playCount: 1),
      ],
      roomsByVenue: {
        'dupla': ['d1', 'd2', 'd3'],
      },
      open: const [
        OpenPassportMilestone(key: 'house:dupla', roomIds: ['d1', 'd2']),
      ],
    );
    expect(kept.grant, isEmpty);
    expect(kept.reverse, isEmpty);

    final undone = planPassportMilestones(
      rules: rules,
      stamps: const [
        RoomStamp(roomId: 'd2', venueId: 'dupla', playCount: 1),
      ],
      roomsByVenue: rooms,
      open: const [
        OpenPassportMilestone(key: 'house:dupla', roomIds: ['d1', 'd2']),
      ],
    );
    expect(undone.reverse, ['house:dupla']);
  });

  test('marco com zero pontos fica desligado', () {
    final plan = planPassportMilestones(
      rules: const PassportRules(
        countMilestones: [PassportCountMilestone(rooms: 5, points: 0)],
        housePoints: 0,
      ),
      stamps: [
        for (var i = 0; i < 5; i++)
          RoomStamp(roomId: 'r$i', venueId: 'v', playCount: 1),
      ],
      roomsByVenue: const {
        'v': ['r0', 'r1'],
      },
      open: const [OpenPassportMilestone(key: 'count:5', roomIds: [])],
    );
    expect(plan.grant, isEmpty);
    expect(plan.reverse, ['count:5']);
  });

  test('pontos do passaporte param no teto e o cashback paga a vaga', () {
    final discount = quotePointSubsidy(
      grossCents: 10000,
      commissionBps: 10000,
      requestedPoints: 9000,
      availablePoints: 9000,
      discountPoints: 9000,
      rates: const ReferralRates(redeemMinPoints: 1, redeemMaxBps: 3000),
    );
    expect(discount.points, 3000);

    final slot = quotePointSubsidy(
      grossCents: 10000,
      commissionBps: 10000,
      requestedPoints: 9000,
      availablePoints: 9000,
      discountPoints: 0,
      rates: const ReferralRates(redeemMinPoints: 1, redeemMaxBps: 3000),
    );
    expect(slot.points, 9000);

    final legacy = quotePointSubsidy(
      grossCents: 10000,
      commissionBps: 10000,
      requestedPoints: 5000,
      availablePoints: 5000,
      rates: const ReferralRates(redeemMinPoints: 1000, redeemMaxBps: 3000),
    );
    expect(legacy.points, 3000);
  });
}
