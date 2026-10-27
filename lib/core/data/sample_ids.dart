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

  static const roomSpMetro = 'room-sp-metro';
  static const roomCwbCofre = 'room-cwb-cofre';

  static const groupSpMetroAlmost = 'grp-sp-metro-almost';
  static const groupSpMetroOpen = 'grp-sp-metro-open';
  static const groupSpCoberturaFull = 'grp-sp-cobertura-full';
  static const groupSpIzakayaAlmost = 'grp-sp-izakaya-almost';

  static const cities = [
    curitiba,
    saoPaulo,
    rioDeJaneiro,
    beloHorizonte,
    portoAlegre,
  ];
}
