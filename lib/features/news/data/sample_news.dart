import 'package:scapematch/core/data/sample_ids.dart';
import 'package:scapematch/features/news/domain/news_item.dart';

/// Ilustrações fictícias do feed. Não são fotos de casas reais.
abstract final class NewsImages {
  static const biblioteca = 'assets/images/news/biblioteca.jpg';
  static const grupo = 'assets/images/news/grupo.jpg';
  static const terror = 'assets/images/news/terror.jpg';
  static const steampunk = 'assets/images/news/steampunk.jpg';
  static const egito = 'assets/images/news/egito.jpg';
  static const scifi = 'assets/images/news/scifi.jpg';
}

/// Ids estáveis para os testes do feed.
abstract final class SampleNewsIds {
  static const cwbBiblioteca = 'news-cwb-biblioteca';
  static const cwbCofreHorario = 'news-cwb-cofre-horario';
  static const cwbOperaPromo = 'news-cwb-opera-promo';
  static const cwbRanking = 'news-cwb-ranking';
  static const cwbLab = 'news-cwb-lab';
  static const cwbGrade = 'news-cwb-grade';
  static const cwbAniversario = 'news-cwb-aniversario';
  static const cwbNoite = 'news-cwb-noite';
  static const cwbEgito = 'news-cwb-egito';
  static const cwbCombo = 'news-cwb-combo';
  static const spLinha = 'news-sp-linha';
  static const spPromo = 'news-sp-promo';
  static const rjEncontro = 'news-rj-encontro';
  static const rjHorario = 'news-rj-horario';
  static const bhPromo = 'news-bh-promo';
  static const poaEvento = 'news-poa-evento';
}

/// Dez notícias em Curitiba e mais algumas nas outras cidades de exemplo.
///
/// Texto, casas e links são inventados. As datas são relativas a [now], o
/// mesmo relógio dos grupos de exemplo. Nada aqui foi copiado de um site.
List<NewsItem> buildSampleNews(DateTime now) {
  const curitiba = 'Curitiba';
  const saoPaulo = 'São Paulo';
  const rio = 'Rio de Janeiro';
  const beloHorizonte = 'Belo Horizonte';
  const portoAlegre = 'Porto Alegre';

  return [
    _item(
      id: SampleNewsIds.cwbBiblioteca,
      title: 'Sala nova: A Biblioteca Proibida',
      summary:
          'O Portal do Batel inventou uma sala entre estantes que se movem. '
          'A estreia de exemplo é só neste feed, não na grade de horários.',
      category: NewsCategory.newRoom,
      houseName: 'Portal do Batel',
      cityId: SampleIds.curitiba,
      cityName: curitiba,
      image: NewsImages.biblioteca,
      publishedAt: now.subtract(const Duration(hours: 2)),
      sourceKind: NewsSourceKind.website,
      sourceUrl: 'https://exemplo.scapematch.invalid/batel/biblioteca',
    ),
    _item(
      id: SampleNewsIds.cwbCofreHorario,
      title: 'O Cofre do Café abre mais um domingo',
      summary:
          'A casa da Rua XV publicou, no exemplo, um horário extra de domingo '
          'à tarde para O Cofre do Café. A sessão ainda não está no catálogo.',
      category: NewsCategory.schedule,
      houseName: 'Mistério da Rua XV',
      cityId: SampleIds.curitiba,
      cityName: curitiba,
      image: NewsImages.grupo,
      publishedAt: now.subtract(const Duration(hours: 5)),
      sourceKind: NewsSourceKind.website,
      sourceUrl: 'https://exemplo.scapematch.invalid/rua-xv/cofre-domingo',
    ),
    _item(
      id: SampleNewsIds.cwbOperaPromo,
      title: 'Terça do Ópera com preço de exemplo',
      summary:
          'Na terça, a segunda cadeira de Enigma no Ópera sai pela metade do '
          'valor fictício. Não há cobrança: o número existe só para o cartão.',
      category: NewsCategory.promotion,
      houseName: 'Portal do Batel',
      cityId: SampleIds.curitiba,
      cityName: curitiba,
      image: NewsImages.steampunk,
      publishedAt: now.subtract(const Duration(days: 1)),
      sourceKind: NewsSourceKind.instagram,
      sourceUrl: 'https://instagram.example.invalid/p/ficticio-opera',
    ),
    _item(
      id: SampleNewsIds.cwbRanking,
      title: 'Ranking fictício das salas mais pedidas',
      summary:
          'Uma lista inventada da semana: o Cofre, o Laboratório e o Ópera. '
          'Não veio de avaliação de cliente nenhum.',
      category: NewsCategory.event,
      houseName: 'Mistério da Rua XV',
      cityId: SampleIds.curitiba,
      cityName: curitiba,
      image: NewsImages.terror,
      publishedAt: now.subtract(const Duration(hours: 3)),
      sourceKind: NewsSourceKind.manual,
    ),
    _item(
      id: SampleNewsIds.cwbLab,
      title: 'O Laboratório do Botânico ganha ala noturna',
      summary:
          'A sala de plantas impossíveis ganhou, no exemplo, um corredor que '
          'só abre depois das 21h. Ainda é texto de feed, não um horário novo.',
      category: NewsCategory.newRoom,
      houseName: 'Mistério da Rua XV',
      cityId: SampleIds.curitiba,
      cityName: curitiba,
      image: NewsImages.scifi,
      publishedAt: now.subtract(const Duration(minutes: 20)),
      sourceKind: NewsSourceKind.website,
      sourceUrl: 'https://exemplo.scapematch.invalid/rua-xv/laboratorio',
    ),
    _item(
      id: SampleNewsIds.cwbGrade,
      title: 'A grade de sexta no Batel vai até mais tarde',
      summary:
          'O Portal do Batel esticou, no exemplo, a sexta até as 23h. Esta '
          'notícia não tem foto: a ilustração é desenhada pelo app.',
      category: NewsCategory.schedule,
      houseName: 'Portal do Batel',
      cityId: SampleIds.curitiba,
      cityName: curitiba,
      publishedAt: now.subtract(const Duration(hours: 8)),
      sourceKind: NewsSourceKind.website,
      sourceUrl: 'https://exemplo.scapematch.invalid/batel/sexta',
    ),
    _item(
      id: SampleNewsIds.cwbAniversario,
      title: 'Aniversário de exemplo: a quarta cadeira sai por conta da casa',
      summary:
          'A Mistério da Rua XV comemora um aniversário inventado. Num grupo '
          'de quatro, a última cadeira não entra na conta fictícia.',
      category: NewsCategory.promotion,
      houseName: 'Mistério da Rua XV',
      cityId: SampleIds.curitiba,
      cityName: curitiba,
      image: NewsImages.grupo,
      publishedAt: now.subtract(const Duration(days: 2)),
      sourceKind: NewsSourceKind.instagram,
      sourceUrl: 'https://instagram.example.invalid/p/ficticio-aniversario',
    ),
    _item(
      id: SampleNewsIds.cwbNoite,
      title: 'Noite steampunk de portas abertas',
      summary:
          'Um encontro de exemplo no Batel, sem sessão marcada e sem vaga de '
          'jogo. É evento da casa, não um grupo para entrar.',
      category: NewsCategory.event,
      houseName: 'Portal do Batel',
      cityId: SampleIds.curitiba,
      cityName: curitiba,
      image: NewsImages.steampunk,
      publishedAt: now.subtract(const Duration(hours: 6)),
      sourceKind: NewsSourceKind.instagram,
      sourceUrl: 'https://instagram.example.invalid/p/ficticio-steampunk',
    ),
    _item(
      id: SampleNewsIds.cwbEgito,
      title: 'Sala nova: a Câmara do Faraó',
      summary:
          'O Batel estreou, só nesta história, uma sala de areia e relógios '
          'de sol. O nome não existe fora do ScapeMatch.',
      category: NewsCategory.newRoom,
      houseName: 'Portal do Batel',
      cityId: SampleIds.curitiba,
      cityName: curitiba,
      image: NewsImages.egito,
      publishedAt: now.subtract(const Duration(days: 4)),
      sourceKind: NewsSourceKind.website,
      sourceUrl: 'https://exemplo.scapematch.invalid/batel/farao',
    ),
    _item(
      id: SampleNewsIds.cwbCombo,
      title: 'Combo de exemplo: café e o Cofre no mesmo fim de tarde',
      summary:
          'Quem jogar O Cofre do Café ganha, no texto, um café da casa. A '
          'curadoria manual inventou o combo. Não há link de origem.',
      category: NewsCategory.promotion,
      houseName: 'Mistério da Rua XV',
      cityId: SampleIds.curitiba,
      cityName: curitiba,
      image: NewsImages.biblioteca,
      publishedAt: now.subtract(const Duration(minutes: 30)),
      sourceKind: NewsSourceKind.manual,
    ),
    _item(
      id: SampleNewsIds.spLinha,
      title: 'Sala nova: A Linha que não existe',
      summary:
          'A Escape Augusta anunciou, no exemplo, uma sala irmã do Metrô '
          'Perdido. Ela ainda não entra na lista de quem vai criar grupo.',
      category: NewsCategory.newRoom,
      houseName: 'Escape Augusta',
      cityId: SampleIds.saoPaulo,
      cityName: saoPaulo,
      image: NewsImages.scifi,
      publishedAt: now.subtract(const Duration(days: 1)),
      sourceKind: NewsSourceKind.website,
      sourceUrl: 'https://exemplo.scapematch.invalid/augusta/linha',
    ),
    _item(
      id: SampleNewsIds.spPromo,
      title: 'Quinta do terror com preço de exemplo',
      summary:
          'A Sala 25 Liberdade baixou, só nesta ficção, o valor da quinta à '
          'noite. O desconto não altera o preço gravado na sala.',
      category: NewsCategory.promotion,
      houseName: 'Sala 25 Liberdade',
      cityId: SampleIds.saoPaulo,
      cityName: saoPaulo,
      image: NewsImages.terror,
      publishedAt: now.subtract(const Duration(hours: 3)),
      sourceKind: NewsSourceKind.instagram,
      sourceUrl: 'https://instagram.example.invalid/p/ficticio-terror',
    ),
    _item(
      id: SampleNewsIds.rjEncontro,
      title: 'Encontro fictício de equipes na calçada',
      summary:
          'A Chave de Copacabana chama, no exemplo, as equipes para uma foto '
          'antes do jogo. Não é uma sessão e não reserva horário.',
      category: NewsCategory.event,
      houseName: 'Chave de Copacabana',
      cityId: SampleIds.rioDeJaneiro,
      cityName: rio,
      image: NewsImages.grupo,
      publishedAt: now.subtract(const Duration(hours: 5)),
      sourceKind: NewsSourceKind.manual,
    ),
    _item(
      id: SampleNewsIds.rjHorario,
      title: 'O Bond Quebrado ganha um horário de manhã',
      summary:
          'A Escuridão de Santa Teresa abriu, no exemplo, um início às 10h. '
          'O catálogo do app continua com os horários que já tinha.',
      category: NewsCategory.schedule,
      houseName: 'Escuridão de Santa Teresa',
      cityId: SampleIds.rioDeJaneiro,
      cityName: rio,
      image: NewsImages.terror,
      publishedAt: now.subtract(const Duration(days: 2)),
      sourceKind: NewsSourceKind.website,
      sourceUrl: 'https://exemplo.scapematch.invalid/santa-teresa/manha',
    ),
    _item(
      id: SampleNewsIds.bhPromo,
      title: 'Happy hour de exemplo no Bar do Mercado',
      summary:
          'A Enigma Savassi inventou um desconto entre 18h e 19h. Belo '
          'Horizonte não tem outra notícia de exemplo nesta versão.',
      category: NewsCategory.promotion,
      houseName: 'Enigma Savassi',
      cityId: SampleIds.beloHorizonte,
      cityName: beloHorizonte,
      image: NewsImages.biblioteca,
      publishedAt: now.subtract(const Duration(hours: 12)),
      sourceKind: NewsSourceKind.instagram,
      sourceUrl: 'https://instagram.example.invalid/p/ficticio-savassi',
    ),
    _item(
      id: SampleNewsIds.poaEvento,
      title: 'Piquenique fictício antes da Estufa',
      summary:
          'O Clube da Redenção marca um encontro no parque, uma hora antes '
          'da sessão. Porto Alegre não tem promoção de exemplo.',
      category: NewsCategory.event,
      houseName: 'Clube da Redenção',
      cityId: SampleIds.portoAlegre,
      cityName: portoAlegre,
      image: NewsImages.grupo,
      publishedAt: now.subtract(const Duration(hours: 26)),
      sourceKind: NewsSourceKind.manual,
    ),
  ];
}

NewsItem _item({
  required String id,
  required String title,
  required String summary,
  required NewsCategory category,
  required String houseName,
  required String cityId,
  required String cityName,
  required DateTime publishedAt,
  required NewsSourceKind sourceKind,
  String? image,
  String? sourceUrl,
}) {
  return NewsItem(
    id: id,
    title: title,
    summary: summary,
    category: category,
    houseName: houseName,
    cityId: cityId,
    cityName: cityName,
    image: image,
    publishedAt: publishedAt,
    sourceUrl: sourceUrl,
    sourceKind: sourceKind,
  );
}
