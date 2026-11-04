/// Molduras em que a foto da sala é desenhada.
///
/// Os números saem do layout do app do jogador:
/// - [card] é a foto do carrossel (`roomCardWidth` × 168).
/// - [hero] é a capa do detalhe no celular de 390 px, com 280 px de altura.
/// - [heroWide] é a capa no desktop de 1440 px: a janela menos
///   as margens de 32 px e o painel de 340 px, com 380 px de altura.
/// - [gallery] é a miniatura da faixa no celular (148 × 112).
/// - [galleryWide] é a miniatura da grade no desktop (240 × 156).
enum RoomFrame { card, hero, heroWide, gallery, galleryWide }

extension RoomFrameBox on RoomFrame {
  int get width {
    return switch (this) {
      RoomFrame.card => 300,
      RoomFrame.hero => 390,
      RoomFrame.heroWide => 1036,
      RoomFrame.gallery => 148,
      RoomFrame.galleryWide => 240,
    };
  }

  int get height {
    return switch (this) {
      RoomFrame.card => 168,
      RoomFrame.hero => 280,
      RoomFrame.heroWide => 380,
      RoomFrame.gallery => 112,
      RoomFrame.galleryWide => 156,
    };
  }

  double get aspect => width / height;

  String get labelPt {
    return switch (this) {
      RoomFrame.card => 'Card',
      RoomFrame.hero => 'Capa',
      RoomFrame.heroWide => 'Capa larga',
      RoomFrame.gallery => 'Galeria',
      RoomFrame.galleryWide => 'Galeria larga',
    };
  }
}
