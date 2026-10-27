import 'package:scapematch/core/data/fake_database.dart';
import 'package:scapematch/core/data/sample_ids.dart';
import 'package:scapematch/features/catalog/domain/difficulty.dart';
import 'package:scapematch/features/catalog/domain/escape_house.dart';
import 'package:scapematch/features/catalog/domain/escape_room.dart';
import 'package:scapematch/features/catalog/domain/time_slot.dart';
import 'package:scapematch/features/cities/domain/city.dart';
import 'package:scapematch/features/groups/domain/group.dart';
import 'package:scapematch/features/groups/domain/participant.dart';

/// Fictional catalog used until real venue data exists.
///
/// Nothing in this file comes from an escape-room website. Names, schedules,
/// and groups are invented so the screens can be built and tested. Replacing
/// [buildSampleDatabase] is the intended way to plug in another source.
FakeDatabase buildSampleDatabase() {
  final curitiba = _city(SampleIds.curitiba, 'Curitiba', 'PR', 'Paraná');
  final saoPaulo = _city(SampleIds.saoPaulo, 'São Paulo', 'SP', 'São Paulo');
  final rio = _city(
    SampleIds.rioDeJaneiro,
    'Rio de Janeiro',
    'RJ',
    'Rio de Janeiro',
  );
  final beloHorizonte = _city(
    SampleIds.beloHorizonte,
    'Belo Horizonte',
    'MG',
    'Minas Gerais',
  );
  final portoAlegre = _city(
    SampleIds.portoAlegre,
    'Porto Alegre',
    'RS',
    'Rio Grande do Sul',
  );

  final ruaXv = _house('cwb-rua-xv', curitiba, 'Mistério da Rua XV', 'Centro');
  final batel = _house('cwb-batel', curitiba, 'Portal do Batel', 'Batel');
  final augusta = _house(
    'sp-augusta',
    saoPaulo,
    'Escape Augusta',
    'Consolação',
  );
  final liberdade = _house(
    'sp-liberdade',
    saoPaulo,
    'Sala 25 Liberdade',
    'Liberdade',
  );
  final copacabana = _house(
    'rj-copa',
    rio,
    'Chave de Copacabana',
    'Copacabana',
  );
  final santaTeresa = _house(
    'rj-santa',
    rio,
    'Escuridão de Santa Teresa',
    'Santa Teresa',
  );
  final savassi = _house(
    'bh-savassi',
    beloHorizonte,
    'Enigma Savassi',
    'Savassi',
  );
  final mina = _house('bh-mina', beloHorizonte, 'Mina Central', 'Centro');
  final cais = _house(
    'poa-cais',
    portoAlegre,
    'Cais do Mistério',
    'Centro Histórico',
  );
  final redencao = _house(
    SampleIds.housePoaRedencao,
    portoAlegre,
    'Clube da Redenção',
    'Bom Fim',
  );

  final cofre = _room(
    SampleIds.roomCwbCofre,
    ruaXv,
    'O Cofre do Café',
    'Um café que fecha a porta sozinho',
    6,
    60,
    Difficulty.medium,
  );
  final laboratorio = _room(
    'room-cwb-lab',
    ruaXv,
    'O Laboratório do Botânico',
    'Plantas que não deveriam existir',
    5,
    70,
    Difficulty.hard,
  );
  final opera = _room(
    'room-cwb-opera',
    batel,
    'Enigma no Ópera',
    'Uma noite que não acaba',
    8,
    60,
    Difficulty.easy,
  );
  final metro = _room(
    SampleIds.roomSpMetro,
    augusta,
    'Metrô Perdido',
    'A linha que sumiu do mapa',
    6,
    75,
    Difficulty.hard,
  );
  final cobertura = _room(
    'room-sp-cobertura',
    augusta,
    'Cobertura da Paulista',
    'Um jantar no último andar',
    4,
    60,
    Difficulty.medium,
  );
  final izakaya = _room(
    'room-sp-izakaya',
    liberdade,
    'O Izakaya Secreto',
    'O reservado dos fundos',
    5,
    60,
    Difficulty.medium,
  );
  final apartamento = _room(
    'room-rj-apartamento',
    copacabana,
    'O Apartamento da Avenida',
    'A janela que não abre',
    6,
    60,
    Difficulty.medium,
  );
  final bond = _room(
    'room-rj-bond',
    santaTeresa,
    'O Bond Quebrado',
    'O último bonde da serra',
    7,
    80,
    Difficulty.hard,
  );
  final bar = _room(
    'room-bh-bar',
    savassi,
    'O Bar do Mercado',
    'A conta que não fecha',
    5,
    50,
    Difficulty.easy,
  );
  final elevador = _room(
    'room-bh-elevador',
    mina,
    'O Elevador da Serra',
    'A descida que demora demais',
    8,
    75,
    Difficulty.hard,
  );
  final porao = _room(
    'room-poa-porao',
    cais,
    'O Porão do Cais',
    'Caixas que chegaram sem dono',
    6,
    60,
    Difficulty.medium,
  );
  final estufa = _room(
    SampleIds.roomPoaEstufa,
    redencao,
    'A Estufa',
    'O jardim que trancou a porta',
    4,
    45,
    Difficulty.easy,
  );

  final slotCofreSat = _slot('slot-cwb-cofre-sat', cofre.id, 7, 19);
  final slotCofreSun = _slot('slot-cwb-cofre-sun', cofre.id, 8, 16);
  final slotLabSat = _slot('slot-cwb-lab-sat', laboratorio.id, 7, 21);
  final slotOperaFri = _slot('slot-cwb-opera-fri', opera.id, 6, 20);
  final slotOperaSat = _slot('slot-cwb-opera-sat', opera.id, 7, 18);
  final slotMetroSat = _slot('slot-sp-metro-sat', metro.id, 7, 18, 30);
  final slotMetroSun = _slot('slot-sp-metro-sun', metro.id, 8, 15);
  final slotCoberturaFri = _slot(
    'slot-sp-cobertura-fri',
    cobertura.id,
    6,
    19,
    30,
  );
  final slotIzakayaSat = _slot('slot-sp-izakaya-sat', izakaya.id, 7, 20);
  final slotIzakayaSun = _slot('slot-sp-izakaya-sun', izakaya.id, 8, 17);
  final slotAptoSat = _slot('slot-rj-apto-sat', apartamento.id, 7, 17);
  final slotAptoFri = _slot('slot-rj-apto-fri', apartamento.id, 6, 21);
  final slotBondSun = _slot('slot-rj-bond-sun', bond.id, 8, 16);
  final slotBondSat = _slot('slot-rj-bond-sat', bond.id, 7, 19);
  final slotBarFri = _slot('slot-bh-bar-fri', bar.id, 6, 19);
  final slotBarSat = _slot('slot-bh-bar-sat', bar.id, 7, 16);
  final slotElevadorSun = _slot('slot-bh-elevador-sun', elevador.id, 8, 18);
  final slotElevadorSat = _slot('slot-bh-elevador-sat', elevador.id, 7, 20, 30);
  final slotPoraoSat = _slot('slot-poa-porao-sat', porao.id, 7, 19);
  final slotPoraoSun = _slot('slot-poa-porao-sun', porao.id, 8, 15, 30);
  final slotEstufaFri = _slot('slot-poa-estufa-fri', estufa.id, 6, 18);
  final slotEstufaSat = _slot('slot-poa-estufa-sat', estufa.id, 7, 21);
  final slotEstufaFree = _slot(SampleIds.slotPoaEstufaFree, estufa.id, 8, 16);

  final groups = [
    _group(
      id: 'grp-cwb-cofre-almost',
      city: curitiba,
      house: ruaXv,
      room: cofre,
      slot: slotCofreSat,
      totalSpots: 5,
      names: ['Marina', 'Caio', 'Helena', 'Davi'],
    ),
    _group(
      id: 'grp-cwb-cofre-open',
      city: curitiba,
      house: ruaXv,
      room: cofre,
      slot: slotCofreSun,
      totalSpots: 6,
      names: ['Lívia', 'Bruno'],
    ),
    _group(
      id: 'grp-cwb-lab-full',
      city: curitiba,
      house: ruaXv,
      room: laboratorio,
      slot: slotLabSat,
      totalSpots: 5,
      names: ['Ana', 'Pedro', 'Rita', 'Igor', 'Sofia'],
    ),
    _group(
      id: 'grp-cwb-opera-almost',
      city: curitiba,
      house: batel,
      room: opera,
      slot: slotOperaFri,
      totalSpots: 8,
      names: ['Teo', 'Nina', 'Otto', 'Bia', 'Leo', 'Maya'],
    ),
    _group(
      id: 'grp-cwb-opera-open',
      city: curitiba,
      house: batel,
      room: opera,
      slot: slotOperaSat,
      totalSpots: 8,
      names: ['Caê', 'Vera', 'Nuno'],
    ),
    _group(
      id: SampleIds.groupSpMetroAlmost,
      city: saoPaulo,
      house: augusta,
      room: metro,
      slot: slotMetroSat,
      totalSpots: 6,
      names: ['Lia', 'Miguel', 'Tainá', 'Rafa', 'João'],
    ),
    _group(
      id: SampleIds.groupSpMetroOpen,
      city: saoPaulo,
      house: augusta,
      room: metro,
      slot: slotMetroSun,
      totalSpots: 6,
      names: ['Diego'],
    ),
    _group(
      id: SampleIds.groupSpCoberturaFull,
      city: saoPaulo,
      house: augusta,
      room: cobertura,
      slot: slotCoberturaFri,
      totalSpots: 4,
      names: ['Paula', 'Heitor', 'Lara', 'Otto'],
    ),
    _group(
      id: SampleIds.groupSpIzakayaAlmost,
      city: saoPaulo,
      house: liberdade,
      room: izakaya,
      slot: slotIzakayaSat,
      totalSpots: 5,
      names: ['Yumi', 'Caio', 'Beto'],
    ),
    _group(
      id: 'grp-sp-izakaya-open',
      city: saoPaulo,
      house: liberdade,
      room: izakaya,
      slot: slotIzakayaSun,
      totalSpots: 5,
      names: ['Noemi'],
    ),
    _group(
      id: 'grp-rj-apto-almost',
      city: rio,
      house: copacabana,
      room: apartamento,
      slot: slotAptoSat,
      totalSpots: 6,
      names: ['Íris', 'Tomás', 'Luna', 'Breno'],
    ),
    _group(
      id: 'grp-rj-apto-open',
      city: rio,
      house: copacabana,
      room: apartamento,
      slot: slotAptoFri,
      totalSpots: 5,
      names: ['Gabi'],
    ),
    _group(
      id: 'grp-rj-bond-almost',
      city: rio,
      house: santaTeresa,
      room: bond,
      slot: slotBondSun,
      totalSpots: 7,
      names: ['Duda', 'Enzo', 'Kauê', 'Mel', 'Rui', 'Tina'],
    ),
    _group(
      id: 'grp-rj-bond-full',
      city: rio,
      house: santaTeresa,
      room: bond,
      slot: slotBondSat,
      totalSpots: 7,
      names: ['Ari', 'Bia', 'Cris', 'Dani', 'Eli', 'Fran', 'Guto'],
    ),
    _group(
      id: 'grp-bh-bar-almost',
      city: beloHorizonte,
      house: savassi,
      room: bar,
      slot: slotBarFri,
      totalSpots: 5,
      names: ['Cecília', 'Hugo', 'Nanda', 'Pablo'],
    ),
    _group(
      id: 'grp-bh-bar-open',
      city: beloHorizonte,
      house: savassi,
      room: bar,
      slot: slotBarSat,
      totalSpots: 5,
      names: ['Iara', 'Léo'],
    ),
    _group(
      id: 'grp-bh-elevador-almost',
      city: beloHorizonte,
      house: mina,
      room: elevador,
      slot: slotElevadorSun,
      totalSpots: 8,
      names: ['Alana', 'Beto', 'Cora', 'Davi', 'Eva', 'Felipe'],
    ),
    _group(
      id: 'grp-bh-elevador-open',
      city: beloHorizonte,
      house: mina,
      room: elevador,
      slot: slotElevadorSat,
      totalSpots: 8,
      names: ['Olívia', 'Ravi', 'Sol'],
    ),
    _group(
      id: 'grp-poa-porao-almost',
      city: portoAlegre,
      house: cais,
      room: porao,
      slot: slotPoraoSat,
      totalSpots: 6,
      names: ['Manu', 'Natan', 'Olga', 'Pietro', 'Quésia'],
    ),
    _group(
      id: 'grp-poa-porao-open',
      city: portoAlegre,
      house: cais,
      room: porao,
      slot: slotPoraoSun,
      totalSpots: 6,
      names: ['Rosa', 'Saulo'],
    ),
    _group(
      id: 'grp-poa-estufa-almost',
      city: portoAlegre,
      house: redencao,
      room: estufa,
      slot: slotEstufaFri,
      totalSpots: 4,
      names: ['Téo', 'Valentina', 'Will'],
    ),
    _group(
      id: 'grp-poa-estufa-full',
      city: portoAlegre,
      house: redencao,
      room: estufa,
      slot: slotEstufaSat,
      totalSpots: 4,
      names: ['Alice', 'Benício', 'Clara', 'Dante'],
    ),
  ];

  return FakeDatabase(
    cities: [curitiba, saoPaulo, rio, beloHorizonte, portoAlegre],
    houses: [
      ruaXv,
      batel,
      augusta,
      liberdade,
      copacabana,
      santaTeresa,
      savassi,
      mina,
      cais,
      redencao,
    ],
    rooms: [
      cofre,
      laboratorio,
      opera,
      metro,
      cobertura,
      izakaya,
      apartamento,
      bond,
      bar,
      elevador,
      porao,
      estufa,
    ],
    slots: [
      slotCofreSat,
      slotCofreSun,
      slotLabSat,
      slotOperaFri,
      slotOperaSat,
      slotMetroSat,
      slotMetroSun,
      slotCoberturaFri,
      slotIzakayaSat,
      slotIzakayaSun,
      slotAptoSat,
      slotAptoFri,
      slotBondSun,
      slotBondSat,
      slotBarFri,
      slotBarSat,
      slotElevadorSun,
      slotElevadorSat,
      slotPoraoSat,
      slotPoraoSun,
      slotEstufaFri,
      slotEstufaSat,
      slotEstufaFree,
    ],
    groups: groups,
  );
}

City _city(String id, String name, String stateCode, String stateName) {
  return City(id: id, name: name, stateCode: stateCode, stateName: stateName);
}

EscapeHouse _house(String id, City city, String name, String neighborhood) {
  return EscapeHouse(
    id: id,
    cityId: city.id,
    name: name,
    neighborhood: neighborhood,
  );
}

EscapeRoom _room(
  String id,
  EscapeHouse house,
  String name,
  String theme,
  int capacity,
  int durationMinutes,
  Difficulty difficulty,
) {
  return EscapeRoom(
    id: id,
    houseId: house.id,
    name: name,
    theme: theme,
    capacity: capacity,
    durationMinutes: durationMinutes,
    difficulty: difficulty,
  );
}

TimeSlot _slot(String id, String roomId, int day, int hour, [int minute = 0]) {
  return TimeSlot(
    id: id,
    roomId: roomId,
    startsAt: DateTime(2026, 11, day, hour, minute),
  );
}

Group _group({
  required String id,
  required City city,
  required EscapeHouse house,
  required EscapeRoom room,
  required TimeSlot slot,
  required int totalSpots,
  required List<String> names,
}) {
  assert(house.cityId == city.id, id);
  assert(room.houseId == house.id, id);
  assert(slot.roomId == room.id, id);
  assert(names.isNotEmpty, id);
  assert(names.length <= totalSpots, id);
  assert(totalSpots <= room.capacity, id);
  return Group(
    id: id,
    cityId: city.id,
    cityName: city.name,
    houseId: house.id,
    houseName: house.name,
    neighborhood: house.neighborhood,
    roomId: room.id,
    roomName: room.name,
    roomTheme: room.theme,
    roomCapacity: room.capacity,
    durationMinutes: room.durationMinutes,
    difficulty: room.difficulty,
    slotId: slot.id,
    startsAt: slot.startsAt,
    filledSpots: names.length,
    totalSpots: totalSpots,
    participants: [
      for (var index = 0; index < names.length; index++)
        Participant(
          id: '$id-p$index',
          displayName: names[index],
          isCreator: index == 0,
          isLocalUser: false,
        ),
    ],
  );
}
