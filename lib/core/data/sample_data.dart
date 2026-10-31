import 'package:scapematch/core/data/fake_database.dart';
import 'package:scapematch/core/geo/geo_point.dart';
import 'package:scapematch/core/data/sample_ids.dart';
import 'package:scapematch/features/catalog/domain/difficulty.dart';
import 'package:scapematch/features/catalog/domain/escape_house.dart';
import 'package:scapematch/features/catalog/domain/escape_room.dart';
import 'package:scapematch/features/catalog/domain/room_category.dart';
import 'package:scapematch/features/catalog/domain/time_slot.dart';
import 'package:scapematch/features/catalog/presentation/room_labels.dart';
import 'package:scapematch/features/cities/domain/city.dart';
import 'package:scapematch/features/groups/domain/attendance.dart';
import 'package:scapematch/features/groups/domain/game_type.dart';
import 'package:scapematch/features/groups/domain/group.dart';
import 'package:scapematch/features/groups/domain/group_rules.dart';
import 'package:scapematch/features/groups/domain/participant.dart';

/// Fictional catalog used until real venue data exists.
///
/// Nothing in this file comes from an escape-room website. Names, schedules,
/// and groups are invented so the screens can be built and tested. Replacing
/// [buildSampleDatabase] is the intended way to plug in another source.
///
/// Each city starts with two groups: one almost full and one with more open
/// seats, both within the room capacity. The almost-full group starts 90
/// minutes after [now], inside the refund window. The other starts three
/// days later, outside it. Curitiba ganha mais grupos quase cheios para a
/// janela da Home ter o que rolar. O create-group screen does not offer a
/// free date picker. It lists the catalog slots of the chosen room, and every
/// room keeps several free future times.
FakeDatabase buildSampleDatabase({required DateTime now}) {
  final schedule = _SampleSchedule(now);
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
    RoomCategory.mystery,
    6,
    60,
    Difficulty.medium,
    minimumPlayers: 6,
  );
  final laboratorio = _room(
    'room-cwb-lab',
    ruaXv,
    'O Laboratório do Botânico',
    'Plantas que não deveriam existir',
    RoomCategory.adventure,
    5,
    70,
    Difficulty.hard,
  );
  final sotao = _room(
    'room-cwb-sotao',
    ruaXv,
    'O Sótão da Rua XV',
    'O andar que ninguém aluga',
    RoomCategory.terror,
    5,
    60,
    Difficulty.hard,
  );
  final nave = _room(
    'room-cwb-nave',
    ruaXv,
    'A Nave do Centro',
    'Um porão que virou cabine',
    RoomCategory.scienceFiction,
    6,
    70,
    Difficulty.medium,
  );
  final opera = _room(
    'room-cwb-opera',
    batel,
    'Enigma no Ópera',
    'Uma noite que não acaba',
    RoomCategory.mystery,
    8,
    60,
    Difficulty.easy,
    cancelWindow: const Duration(hours: 24),
  );
  final engrenagem = _room(
    'room-cwb-engrenagem',
    batel,
    'Engrenagem do Batel',
    'Relógios que andam para trás',
    RoomCategory.steampunk,
    6,
    75,
    Difficulty.hard,
  );
  final tumba = _room(
    'room-cwb-tumba',
    batel,
    'A Tumba do Parque',
    'Uma câmara que não está no mapa',
    RoomCategory.egypt,
    6,
    60,
    Difficulty.medium,
  );
  final metro = _room(
    SampleIds.roomSpMetro,
    augusta,
    'Metrô Perdido',
    'A linha que sumiu do mapa',
    RoomCategory.scienceFiction,
    6,
    75,
    Difficulty.hard,
  );
  final cobertura = _room(
    'room-sp-cobertura',
    augusta,
    'Cobertura da Paulista',
    'Um jantar no último andar',
    RoomCategory.mystery,
    4,
    60,
    Difficulty.medium,
  );
  final izakaya = _room(
    'room-sp-izakaya',
    liberdade,
    'O Izakaya Secreto',
    'O reservado dos fundos',
    RoomCategory.mystery,
    5,
    60,
    Difficulty.medium,
  );
  final apartamento = _room(
    'room-rj-apartamento',
    copacabana,
    'O Apartamento da Avenida',
    'A janela que não abre',
    RoomCategory.terror,
    6,
    60,
    Difficulty.medium,
  );
  final bond = _room(
    'room-rj-bond',
    santaTeresa,
    'O Bond Quebrado',
    'O último bonde da serra',
    RoomCategory.adventure,
    7,
    80,
    Difficulty.hard,
  );
  final bar = _room(
    'room-bh-bar',
    savassi,
    'O Bar do Mercado',
    'A conta que não fecha',
    RoomCategory.mystery,
    5,
    50,
    Difficulty.easy,
  );
  final elevador = _room(
    'room-bh-elevador',
    mina,
    'O Elevador da Serra',
    'A descida que demora demais',
    RoomCategory.adventure,
    8,
    75,
    Difficulty.hard,
  );
  final porao = _room(
    'room-poa-porao',
    cais,
    'O Porão do Cais',
    'Caixas que chegaram sem dono',
    RoomCategory.terror,
    6,
    60,
    Difficulty.medium,
  );
  final estufa = _room(
    SampleIds.roomPoaEstufa,
    redencao,
    'A Estufa',
    'O jardim que trancou a porta',
    RoomCategory.adventure,
    4,
    45,
    Difficulty.easy,
  );
  final trilha = _room(
    'room-cwb-trilha',
    batel,
    'A Trilha do Bosque',
    'Um caminho que fecha atrás de você',
    RoomCategory.adventure,
    6,
    70,
    Difficulty.medium,
  );
  final poraoXv = _room(
    'room-cwb-porao',
    ruaXv,
    'O Porão sem Luz',
    'A escada que some no meio',
    RoomCategory.terror,
    5,
    60,
    Difficulty.hard,
  );
  final satelite = _room(
    'room-cwb-satelite',
    batel,
    'O Satélite do Batel',
    'Uma cabine que não responde',
    RoomCategory.scienceFiction,
    6,
    75,
    Difficulty.medium,
  );
  final caldeira = _room(
    'room-cwb-caldeira',
    ruaXv,
    'A Caldeira da XV',
    'Vapor que marca as horas',
    RoomCategory.steampunk,
    6,
    70,
    Difficulty.medium,
  );
  final sarcofago = _room(
    'room-cwb-sarcofago',
    ruaXv,
    'O Sarcófago da XV',
    'Uma tampa que não devia existir',
    RoomCategory.egypt,
    5,
    60,
    Difficulty.hard,
  );
  final antena = _room(
    'room-sp-antena',
    augusta,
    'A Antena da Augusta',
    'O sinal que não volta',
    RoomCategory.scienceFiction,
    5,
    70,
    Difficulty.medium,
  );
  final espelho = _room(
    'room-rj-espelho',
    copacabana,
    'O Espelho de Copacabana',
    'O reflexo que chega atrasado',
    RoomCategory.terror,
    5,
    60,
    Difficulty.medium,
  );
  final ladeira = _room(
    'room-rj-ladeira',
    santaTeresa,
    'A Ladeira da Serra',
    'Os degraus que mudam de lugar',
    RoomCategory.adventure,
    6,
    75,
    Difficulty.hard,
  );
  final cofreSavassi = _room(
    'room-bh-cofre',
    savassi,
    'O Cofre da Savassi',
    'A senha que o bar esqueceu',
    RoomCategory.mystery,
    5,
    60,
    Difficulty.medium,
  );
  final minaAberta = _room(
    'room-bh-mina-aberta',
    mina,
    'A Mina Aberta',
    'Um túnel com o mapa errado',
    RoomCategory.adventure,
    7,
    80,
    Difficulty.hard,
  );
  final armario = _room(
    'room-poa-armario',
    cais,
    'O Armário do Cais',
    'A porta que range sozinha',
    RoomCategory.terror,
    4,
    50,
    Difficulty.easy,
  );
  final bonde = _room(
    'room-poa-bonde',
    redencao,
    'O Bonde do Bom Fim',
    'O trilho que acaba no parque',
    RoomCategory.adventure,
    6,
    70,
    Difficulty.medium,
  );
  final mesaRpg = _room(
    'room-cwb-mesa',
    batel,
    'Mesa longa do Batel',
    'Uma campanha que cabe numa noite',
    RoomCategory.adventure,
    6,
    180,
    Difficulty.medium,
    gameType: GameTypes.rpg,
  );
  final tabuleiro = _room(
    'room-cwb-tabuleiro',
    ruaXv,
    'Clube de tabuleiro da XV',
    'Caixas abertas até o último ônibus',
    RoomCategory.mystery,
    8,
    120,
    Difficulty.easy,
    gameType: GameTypes.boardGame,
  );
  final arenaLaser = _room(
    'room-cwb-arena',
    batel,
    'Arena laser do Parque',
    'Coletes que acendem no escuro',
    RoomCategory.scienceFiction,
    10,
    30,
    Difficulty.easy,
    gameType: GameTypes.laserTag,
  );
  final camara = _room(
    'room-cwb-camara',
    batel,
    'Câmara imersiva do Parque',
    'A sala inteira entra na história',
    RoomCategory.egypt,
    8,
    90,
    Difficulty.medium,
    gameType: GameTypes.immersive,
  );

  final slotCofreSat = schedule.soonSlot('slot-cwb-cofre-sat', cofre.id);
  final slotCofreSun = schedule.free('slot-cwb-cofre-sun', cofre.id, 0);
  final slotLabSat = schedule.free('slot-cwb-lab-sat', laboratorio.id, 0);
  final slotOperaFri = schedule.free('slot-cwb-opera-fri', opera.id, 0);
  final slotOperaSat = schedule.laterSlot('slot-cwb-opera-sat', opera.id);
  final slotMetroSat = schedule.soonSlot('slot-sp-metro-sat', metro.id);
  final slotMetroSun = schedule.free('slot-sp-metro-sun', metro.id, 0);
  final slotCoberturaFri = schedule.laterSlot(
    'slot-sp-cobertura-fri',
    cobertura.id,
  );
  final slotIzakayaSat = schedule.free('slot-sp-izakaya-sat', izakaya.id, 0);
  final slotIzakayaSun = schedule.free('slot-sp-izakaya-sun', izakaya.id, 1);
  final slotIzakayaOverlap = schedule.at(
    SampleIds.slotSpIzakayaOverlap,
    izakaya.id,
    now.add(const Duration(minutes: 100)),
  );
  final slotAptoSat = schedule.soonSlot('slot-rj-apto-sat', apartamento.id);
  final slotAptoFri = schedule.free('slot-rj-apto-fri', apartamento.id, 0);
  final slotBondSun = schedule.laterSlot('slot-rj-bond-sun', bond.id);
  final slotBondSat = schedule.free('slot-rj-bond-sat', bond.id, 0);
  final slotBarFri = schedule.soonSlot('slot-bh-bar-fri', bar.id);
  final slotBarSat = schedule.free('slot-bh-bar-sat', bar.id, 0);
  final slotElevadorSun = schedule.free('slot-bh-elevador-sun', elevador.id, 0);
  final slotElevadorSat = schedule.laterSlot(
    'slot-bh-elevador-sat',
    elevador.id,
  );
  final slotPoraoSat = schedule.free('slot-poa-porao-sat', porao.id, 0);
  final slotPoraoSun = schedule.laterSlot('slot-poa-porao-sun', porao.id);
  final slotEstufaFri = schedule.soonSlot('slot-poa-estufa-fri', estufa.id);
  final slotEstufaSat = schedule.free('slot-poa-estufa-sat', estufa.id, 0);
  final slotEstufaFree = schedule.free(
    SampleIds.slotPoaEstufaFree,
    estufa.id,
    1,
  );
  final slotSotao = schedule.free('slot-cwb-sotao-free', sotao.id, 2);
  final slotNave = schedule.free('slot-cwb-nave-free', nave.id, 2);
  final slotEngrenagem = schedule.free(
    'slot-cwb-engrenagem-free',
    engrenagem.id,
    2,
  );
  final slotTumba = schedule.free('slot-cwb-tumba-free', tumba.id, 2);
  final slotTrilha = schedule.free('slot-cwb-trilha-free', trilha.id, 3);
  final slotPoraoXv = schedule.free('slot-cwb-porao-free', poraoXv.id, 3);
  final slotSatelite = schedule.free('slot-cwb-satelite-free', satelite.id, 3);
  final slotCaldeira = schedule.free('slot-cwb-caldeira-free', caldeira.id, 3);
  final slotSarcofago = schedule.free(
    'slot-cwb-sarcofago-free',
    sarcofago.id,
    3,
  );
  final slotAntena = schedule.free('slot-sp-antena-free', antena.id, 3);
  final slotEspelho = schedule.free('slot-rj-espelho-free', espelho.id, 3);
  final slotLadeira = schedule.free('slot-rj-ladeira-free', ladeira.id, 3);
  final slotCofreSavassi = schedule.free(
    'slot-bh-cofre-free',
    cofreSavassi.id,
    3,
  );
  final slotMinaAberta = schedule.free(
    'slot-bh-mina-aberta-free',
    minaAberta.id,
    3,
  );
  final slotArmario = schedule.free('slot-poa-armario-free', armario.id, 3);
  final slotBonde = schedule.free('slot-poa-bonde-free', bonde.id, 3);
  final slotMesa = schedule.free('slot-cwb-mesa-free', mesaRpg.id, 4);
  final slotTabuleiro = schedule.free(
    'slot-cwb-tabuleiro-free',
    tabuleiro.id,
    4,
  );
  final slotArena = schedule.free('slot-cwb-arena-free', arenaLaser.id, 4);
  final slotCamara = schedule.free('slot-cwb-camara-free', camara.id, 4);
  // Horários fora da grade livre, só para os grupos extras de Curitiba.
  final slotLabQuase = schedule.at(
    'slot-cwb-lab-quase',
    laboratorio.id,
    now.add(const Duration(hours: 6)),
  );
  final slotSotaoQuase = schedule.at(
    'slot-cwb-sotao-quase',
    sotao.id,
    now.add(const Duration(hours: 9)),
  );
  final slotNaveQuase = schedule.at(
    'slot-cwb-nave-quase',
    nave.id,
    now.add(const Duration(hours: 12)),
  );
  final slotEngrenagemQuase = schedule.at(
    'slot-cwb-engrenagem-quase',
    engrenagem.id,
    now.add(const Duration(hours: 18)),
  );
  final slotTumbaQuase = schedule.at(
    'slot-cwb-tumba-quase',
    tumba.id,
    now.add(const Duration(hours: 30)),
  );
  final slotTrilhaQuase = schedule.at(
    'slot-cwb-trilha-quase',
    trilha.id,
    now.add(const Duration(hours: 40)),
  );
  final slotPoraoQuase = schedule.at(
    'slot-cwb-porao-quase',
    poraoXv.id,
    now.add(const Duration(hours: 60)),
  );
  final slotSateliteQuase = schedule.at(
    'slot-cwb-satelite-quase',
    satelite.id,
    now.add(const Duration(hours: 66)),
  );

  // Two groups per city. One is almost full (1 or 2 open seats). The other
  // has more open seats. Curitiba also has eight more almost-full groups so
  // the home window can scroll. They use their own start times.
  final groups = [
    _group(
      now: now,
      id: 'grp-cwb-cofre-almost',
      city: curitiba,
      house: ruaXv,
      room: cofre,
      slot: slotCofreSat,
      totalSpots: 6,
      names: ['Marina', 'Caio', 'Helena', 'Davi', 'Léo'],
    ),
    _group(
      now: now,
      id: 'grp-cwb-opera-open',
      city: curitiba,
      house: batel,
      room: opera,
      slot: slotOperaSat,
      totalSpots: 8,
      names: ['Caê', 'Vera', 'Nuno'],
      note: 'Chegar 15 minutos antes.',
    ),
    _group(
      now: now,
      id: 'grp-cwb-lab-quase',
      city: curitiba,
      house: ruaXv,
      room: laboratorio,
      slot: slotLabQuase,
      totalSpots: 5,
      names: ['Ana', 'Bia', 'Caio', 'Duda'],
    ),
    _group(
      now: now,
      id: 'grp-cwb-sotao-quase',
      city: curitiba,
      house: ruaXv,
      room: sotao,
      slot: slotSotaoQuase,
      totalSpots: 5,
      names: ['Eva', 'Fábio', 'Gabi'],
    ),
    _group(
      now: now,
      id: 'grp-cwb-nave-quase',
      city: curitiba,
      house: ruaXv,
      room: nave,
      slot: slotNaveQuase,
      totalSpots: 6,
      names: ['Hugo', 'Iara', 'Júlio', 'Kai', 'Lara'],
    ),
    _group(
      now: now,
      id: 'grp-cwb-engrenagem-quase',
      city: curitiba,
      house: batel,
      room: engrenagem,
      slot: slotEngrenagemQuase,
      totalSpots: 6,
      names: ['Milo', 'Nina', 'Otto', 'Pietra'],
    ),
    _group(
      now: now,
      id: 'grp-cwb-tumba-imersivo',
      city: curitiba,
      house: batel,
      room: tumba,
      slot: slotTumbaQuase,
      totalSpots: 6,
      names: ['Quim', 'Rita', 'Sara', 'Téo', 'Uma'],
      gameType: GameTypes.immersive,
      roomName: 'Ritual imersivo da tumba',
    ),
    _group(
      now: now,
      id: 'grp-cwb-trilha-laser',
      city: curitiba,
      house: batel,
      room: trilha,
      slot: slotTrilhaQuase,
      totalSpots: 6,
      names: ['Vini', 'Wanda', 'Xande', 'Yara'],
      gameType: GameTypes.laserTag,
      roomName: 'Arena laser da trilha',
    ),
    _group(
      now: now,
      id: 'grp-cwb-porao-rpg',
      city: curitiba,
      house: ruaXv,
      room: poraoXv,
      slot: slotPoraoQuase,
      totalSpots: 5,
      names: ['Zeca', 'Aline', 'Bruno', 'Cris'],
      gameType: GameTypes.rpg,
      roomName: 'Mesa de RPG no porão',
    ),
    _group(
      now: now,
      id: 'grp-cwb-satelite-tabuleiro',
      city: curitiba,
      house: batel,
      room: satelite,
      slot: slotSateliteQuase,
      totalSpots: 6,
      names: ['Dani', 'Elio', 'Fran', 'Guto', 'Hélio'],
      gameType: GameTypes.boardGame,
      roomName: 'Noite de tabuleiro no Batel',
    ),
    _group(
      now: now,
      id: SampleIds.groupSpMetroAlmost,
      city: saoPaulo,
      house: augusta,
      room: metro,
      slot: slotMetroSat,
      totalSpots: 6,
      names: ['Lia', 'Miguel', 'Tainá', 'Rafa', 'João'],
    ),
    _group(
      now: now,
      id: SampleIds.groupSpCoberturaOpen,
      city: saoPaulo,
      house: augusta,
      room: cobertura,
      slot: slotCoberturaFri,
      totalSpots: 4,
      names: ['Paula'],
    ),
    _group(
      now: now,
      id: 'grp-rj-apto-almost',
      city: rio,
      house: copacabana,
      room: apartamento,
      slot: slotAptoSat,
      totalSpots: 6,
      names: ['Íris', 'Tomás', 'Luna', 'Breno'],
    ),
    _group(
      now: now,
      id: 'grp-rj-bond-open',
      city: rio,
      house: santaTeresa,
      room: bond,
      slot: slotBondSun,
      totalSpots: 7,
      names: ['Duda', 'Enzo'],
    ),
    _group(
      now: now,
      id: 'grp-bh-bar-almost',
      city: beloHorizonte,
      house: savassi,
      room: bar,
      slot: slotBarFri,
      totalSpots: 5,
      names: ['Cecília', 'Hugo', 'Nanda', 'Pablo'],
    ),
    _group(
      now: now,
      id: 'grp-bh-elevador-open',
      city: beloHorizonte,
      house: mina,
      room: elevador,
      slot: slotElevadorSat,
      totalSpots: 8,
      names: ['Olívia', 'Ravi', 'Sol'],
    ),
    _group(
      now: now,
      id: 'grp-poa-estufa-almost',
      city: portoAlegre,
      house: redencao,
      room: estufa,
      slot: slotEstufaFri,
      totalSpots: 4,
      names: ['Téo', 'Valentina', 'Will'],
    ),
    _group(
      now: now,
      id: 'grp-poa-porao-open',
      city: portoAlegre,
      house: cais,
      room: porao,
      slot: slotPoraoSun,
      totalSpots: 6,
      names: ['Rosa', 'Saulo'],
    ),
    _group(
      now: now,
      id: 'grp-cwb-cofre-missed',
      city: curitiba,
      house: ruaXv,
      room: cofre,
      slot: schedule.at(
        'slot-cwb-cofre-missed',
        cofre.id,
        now.add(const Duration(days: 5)),
      ),
      totalSpots: 6,
      names: ['Paula', 'Rui'],
      minimumSpots: 6,
      closesAt: now.subtract(const Duration(hours: 2)),
    ),
  ];

  final nearby = _nearbyPlaces(
    now: now,
    schedule: schedule,
    cities: [curitiba, saoPaulo, rio, beloHorizonte, portoAlegre],
  );

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
      ...nearby.houses,
    ],
    rooms: [
      cofre,
      laboratorio,
      sotao,
      nave,
      opera,
      engrenagem,
      tumba,
      metro,
      cobertura,
      izakaya,
      apartamento,
      bond,
      bar,
      elevador,
      porao,
      estufa,
      trilha,
      poraoXv,
      satelite,
      caldeira,
      sarcofago,
      antena,
      espelho,
      ladeira,
      cofreSavassi,
      minaAberta,
      armario,
      bonde,
      mesaRpg,
      tabuleiro,
      arenaLaser,
      camara,
      ...nearby.rooms,
    ],
    slots: _padRoomSlots(schedule, [
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
      slotIzakayaOverlap,
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
      slotSotao,
      slotNave,
      slotEngrenagem,
      slotTumba,
      slotTrilha,
      slotPoraoXv,
      slotSatelite,
      slotCaldeira,
      slotSarcofago,
      slotAntena,
      slotEspelho,
      slotLadeira,
      slotCofreSavassi,
      slotMinaAberta,
      slotArmario,
      slotBonde,
      slotMesa,
      slotTabuleiro,
      slotArena,
      slotCamara,
      slotLabQuase,
      slotSotaoQuase,
      slotNaveQuase,
      slotEngrenagemQuase,
      slotTumbaQuase,
      slotTrilhaQuase,
      slotPoraoQuase,
      slotSateliteQuase,
      ...nearby.slots,
    ]),
    groups: [...groups, ...nearby.groups],
  );
}

City _city(String id, String name, String stateCode, String stateName) {
  return City(id: id, name: name, stateCode: stateCode, stateName: stateName);
}

EscapeHouse _house(String id, City city, String name, String neighborhood) {
  final point = _housePoints[id];
  if (point == null) {
    throw StateError('Casa $id sem ponto no mapa de exemplo.');
  }
  return EscapeHouse(
    id: id,
    cityId: city.id,
    name: name,
    neighborhood: neighborhood,
    latitude: point.$1,
    longitude: point.$2,
  );
}

/// Pontos inventados dentro do bairro, só para o mapa de exemplo.
///
/// Não vêm de site de casa nenhuma. São coordenadas públicas de bairro,
/// deslocadas, para o pino cair na região certa da cidade.
const _housePoints = <String, (double, double)>{
  'cwb-rua-xv': (-25.4296, -49.2712),
  'cwb-batel': (-25.4422, -49.2904),
  'sp-augusta': (-23.5556, -46.6584),
  'sp-liberdade': (-23.5608, -46.6332),
  'rj-copa': (-22.9718, -43.1854),
  'rj-santa': (-22.9208, -43.1866),
  'bh-savassi': (-19.9386, -43.9334),
  'bh-mina': (-19.9172, -43.9348),
  'poa-cais': (-30.0272, -51.2292),
  'poa-redencao': (-30.0342, -51.2162),
};

/// Dez casas por cidade, em anéis de 1,6 km a 14 km, cada uma com um grupo
/// que ainda está se formando. Os horários ficam fora da janela de 2 h,
/// para o par “quase cheio agora / aberto depois” de cada cidade continuar
/// único.
({
  List<EscapeHouse> houses,
  List<EscapeRoom> rooms,
  List<TimeSlot> slots,
  List<Group> groups,
})
_nearbyPlaces({
  required DateTime now,
  required _SampleSchedule schedule,
  required List<City> cities,
}) {
  const labels = <String>[
    'O Relógio',
    'A Chave',
    'O Porão Novo',
    'A Lanterna',
    'O Farol',
    'A Máscara',
    'A Escada',
    'O Espelho Partido',
    'A Biblioteca',
    'O Sinal',
  ];
  const distancesKm = <double>[1.6, 2.4, 3.2, 4.4, 4.9, 6.2, 7.4, 8.8, 11, 14];
  const guestNames = <String>['Ana', 'Beto', 'Cris', 'Duda', 'Eva'];
  final houses = <EscapeHouse>[];
  final rooms = <EscapeRoom>[];
  final slots = <TimeSlot>[];
  final groups = <Group>[];
  for (final city in cities) {
    final center = cityCenters[city.id];
    if (center == null) {
      continue;
    }
    for (var index = 0; index < labels.length; index++) {
      final id = '${city.id}-near-$index';
      final point = offsetKm(
        center,
        kilometers: distancesKm[index],
        bearingDegrees: index * 36,
      );
      final house = EscapeHouse(
        id: id,
        cityId: city.id,
        name: '${labels[index]} de ${city.name}',
        neighborhood: 'Arredores',
        latitude: point.latitude,
        longitude: point.longitude,
      );
      final room = _room(
        'room-$id',
        house,
        labels[index],
        'Uma sala de exemplo nos arredores',
        RoomCategory.values[index % RoomCategory.values.length],
        6,
        60,
        Difficulty.medium,
        minimumPlayers: 6,
      );
      final startsAt = now.add(Duration(hours: 36 + (index * 5)));
      final slot = schedule.at('slot-$id', room.id, startsAt);
      final group = _group(
        now: now,
        id: 'grp-$id',
        city: city,
        house: house,
        room: room,
        slot: slot,
        totalSpots: 6,
        names: guestNames,
        minimumSpots: 6,
      );
      houses.add(house);
      rooms.add(room);
      slots.add(slot);
      groups.add(group);
    }
  }
  return (houses: houses, rooms: rooms, slots: slots, groups: groups);
}

EscapeRoom _room(
  String id,
  EscapeHouse house,
  String name,
  String theme,
  RoomCategory category,
  int capacity,
  int durationMinutes,
  Difficulty difficulty, {
  String gameType = GameTypes.escapeRoom,
  int minimumPlayers = 2,
  Duration cancelWindow = const Duration(hours: 2),
}) {
  return EscapeRoom(
    id: id,
    houseId: house.id,
    name: name,
    theme: theme,
    category: category,
    capacity: capacity,
    durationMinutes: durationMinutes,
    difficulty: difficulty,
    priceCents: _priceCents(capacity, difficulty),
    gameType: gameType,
    minimumPlayers: minimumPlayers,
    cancelWindow: cancelWindow,
  );
}

int _priceCents(int capacity, Difficulty difficulty) {
  final base = switch (difficulty) {
    Difficulty.easy => 8900,
    Difficulty.medium => 10900,
    Difficulty.hard => 12900,
  };
  return base + (capacity * 100);
}

/// How many future start times the create-group sheet must offer.
///
/// One of them may already host the city's sample group. The rest stay
/// empty. A past slot is added on top so "this time already started" can
/// be tried without filling the future grid.
const _minimumFutureSlotsPerRoom = 4;

class _SampleSchedule {
  _SampleSchedule(this.now);

  final DateTime now;

  DateTime get soonAt => _minute(now.add(const Duration(minutes: 90)));

  DateTime get laterAt => _minute(now.add(const Duration(days: 3, hours: 6)));

  DateTime get past => _minute(now.subtract(const Duration(hours: 3)));

  DateTime freeAt(int index) {
    return _minute(now.add(Duration(hours: 26 + (index * 24))));
  }

  TimeSlot soonSlot(String id, String roomId) => _take(id, roomId, soonAt);

  TimeSlot laterSlot(String id, String roomId) => _take(id, roomId, laterAt);

  TimeSlot free(String id, String roomId, int index) {
    return _take(id, roomId, freeAt(index));
  }

  TimeSlot at(String id, String roomId, DateTime startsAt) {
    return _take(id, roomId, _minute(startsAt));
  }

  TimeSlot _take(String id, String roomId, DateTime startsAt) {
    return TimeSlot(id: id, roomId: roomId, startsAt: startsAt);
  }
}

DateTime _minute(DateTime value) {
  return DateTime(value.year, value.month, value.day, value.hour, value.minute);
}

List<TimeSlot> _padRoomSlots(_SampleSchedule schedule, List<TimeSlot> slots) {
  final byRoom = <String, List<TimeSlot>>{};
  for (final slot in slots) {
    byRoom.putIfAbsent(slot.roomId, () => []).add(slot);
  }
  final padded = [...slots];
  for (final entry in byRoom.entries) {
    final used = entry.value.map((slot) => slot.startsAt).toSet();
    final roomId = entry.key;
    if (used.add(schedule.past)) {
      padded.add(
        TimeSlot(id: '$roomId-past', roomId: roomId, startsAt: schedule.past),
      );
    }
    var future = entry.value
        .where((slot) => slot.startsAt.isAfter(schedule.now))
        .length;
    var index = 0;
    while (future < _minimumFutureSlotsPerRoom && index < 24) {
      final startsAt = schedule.freeAt(index);
      index += 1;
      if (!startsAt.isAfter(schedule.now) || !used.add(startsAt)) {
        continue;
      }
      padded.add(
        TimeSlot(
          id: '$roomId-extra-$index',
          roomId: roomId,
          startsAt: startsAt,
        ),
      );
      future += 1;
    }
  }
  return padded;
}

Group _group({
  required String id,
  required City city,
  required EscapeHouse house,
  required EscapeRoom room,
  required TimeSlot slot,
  required int totalSpots,
  required List<String> names,
  String note = '',
  String gameType = GameTypes.escapeRoom,
  String? roomName,
  int? minimumSpots,
  DateTime? closesAt,
  required DateTime now,
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
    roomName: roomName ?? room.name,
    roomTheme: room.theme,
    roomCapacity: room.capacity,
    durationMinutes: room.durationMinutes,
    difficulty: room.difficulty,
    slotId: slot.id,
    startsAt: slot.startsAt,
    filledSpots: names.length,
    totalSpots: totalSpots,
    priceCents: room.priceCents,
    gameType: gameType,
    note: note,
    minimumSpots: minimumSpots ?? room.minimumPlayers,
    closesAt:
        closesAt ?? GroupRules.closeDeadline(startsAt: slot.startsAt, now: now),
    cancelWindow: room.cancelWindow,
    streetAddress: house.streetAddress,
    coverAsset: roomCategoryImage(room.category),
    participants: [
      for (var index = 0; index < names.length; index++)
        Participant(
          id: '$id-p$index',
          displayName: names[index],
          isCreator: index == 0,
          isLocalUser: false,
          attendance: index == 0
              ? AttendanceStatus.confirmed
              : AttendanceStatus.joined,
        ),
    ],
  );
}
