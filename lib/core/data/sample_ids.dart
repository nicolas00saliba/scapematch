/// Ids of the fictional sample used by tests and the in-memory database.
///
/// Keeping them in one place avoids typos between the seed and the tests.
abstract final class SampleIds {
  static const curitiba = 'curitiba';
  static const saoPaulo = 'sao-paulo';
  static const rioDeJaneiro = 'rio-de-janeiro';
  static const beloHorizonte = 'belo-horizonte';
  static const portoAlegre = 'porto-alegre';

  static const housePoaRedencao = 'poa-redencao';
  static const roomPoaEstufa = 'room-poa-estufa';
  static const slotPoaEstufaFree = 'slot-poa-estufa-free';
  static const slotPoaEstufaTaken = 'slot-poa-estufa-fri';

  static const houseSpAugusta = 'sp-augusta';
  static const houseSpLiberdade = 'sp-liberdade';
  static const roomSpIzakaya = 'room-sp-izakaya';
  static const roomSpCobertura = 'room-sp-cobertura';
  static const slotSpMetroSun = 'slot-sp-metro-sun';
  static const slotSpCoberturaFri = 'slot-sp-cobertura-fri';

  static const roomSpMetro = 'room-sp-metro';
  static const roomCwbCofre = 'room-cwb-cofre';

  static const groupSpMetroAlmost = 'grp-sp-metro-almost';
  static const groupSpCoberturaOpen = 'grp-sp-cobertura-open';
  static const groupCwbCofreAlmost = 'grp-cwb-cofre-almost';

  /// Starts about 100 minutes after the sample clock, inside the Metrô
  /// Perdido session, so joining that group and then booking this slot
  /// overlaps.
  static const slotSpIzakayaOverlap = 'slot-sp-izakaya-overlap';

  /// A start time that is already in the past for the sample clock.
  static const slotSpMetroPast = 'room-sp-metro-past';

  static const cities = [
    curitiba,
    saoPaulo,
    rioDeJaneiro,
    beloHorizonte,
    portoAlegre,
  ];
}
