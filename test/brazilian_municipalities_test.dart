import 'package:flutter_test/flutter_test.dart';
import 'package:scapematch/features/cities/data/brazilian_municipalities.dart';

void main() {
  test(
    'o catálogo tem todos os municípios do IBGE e preserva os ids antigos',
    () {
      expect(municipiosIbgeV1.length, municipiosIbgeCount);
      expect(municipiosIbgeCount, 5571);
      expect(brazilianStates, hasLength(27));

      final ids = {for (final city in municipiosIbgeV1) city.id};
      final codes = {for (final city in municipiosIbgeV1) city.ibge};
      expect(ids, hasLength(municipiosIbgeCount));
      expect(codes, hasLength(municipiosIbgeCount));

      expect(municipalityById('curitiba')?.ibge, 4106902);
      expect(municipalityById('sao-paulo')?.ibge, 3550308);
      expect(municipalityById('rio-de-janeiro')?.ibge, 3304557);
      expect(municipalityById('belo-horizonte')?.ibge, 3106200);
      expect(municipalityById('porto-alegre')?.ibge, 4314902);

      expect(municipalityById('campinas-sp')?.name, 'Campinas');
      expect(municipalityById('londrina-pr')?.stateCode, 'PR');
      expect(municipalityById('brasilia-df')?.name, 'Brasília');
      expect(
        municipalityById('boa-esperanca-do-norte-mt')?.name,
        'Boa Esperança do Norte',
      );
    },
  );

  test('a busca ignora acento e resolve nomes únicos ou com UF', () {
    expect(resolveMunicipalityId('Curitiba'), 'curitiba');
    expect(resolveMunicipalityId('São Paulo'), 'sao-paulo');
    expect(resolveMunicipalityId('sao-paulo'), 'sao-paulo');
    expect(resolveMunicipalityId('Londrina'), 'londrina-pr');
    expect(resolveMunicipalityId('campinas-sp'), 'campinas-sp');
    expect(resolveMunicipalityId('Campinas, SP'), 'campinas-sp');
    expect(resolveMunicipalityId('Florianópolis'), 'florianopolis-sc');
    expect(resolveMunicipalityId('Florianopolis'), 'florianopolis-sc');
    expect(
      resolveMunicipalityId("Olho d'Água do Borges"),
      'olho-d-agua-do-borges-rn',
    );
    expect(
      resolveMunicipalityId('olho dagua do borges'),
      'olho-d-agua-do-borges-rn',
    );

    expect(resolveMunicipalityId('Bom Jesus'), isNull);
    expect(resolveMunicipalityId('Bom Jesus, PI'), 'bom-jesus-pi');
    expect(resolveMunicipalityId('Bom Jesus SC'), 'bom-jesus-sc');
    expect(resolveMunicipalityId('Londrina', stateCode: 'SP'), isNull);

    final withoutAccent = searchMunicipalities(query: 'sao luis do quitunde');
    expect(
      withoutAccent.any((city) => city.id == 'sao-luis-do-quitunde-al'),
      isTrue,
    );

    final inParana = searchMunicipalities(stateCode: 'PR', query: 'londrina');
    expect(inParana, isNotEmpty);
    expect(inParana.first.id, 'londrina-pr');

    final curitiba = searchMunicipalities(stateCode: 'PR', query: 'curitib');
    expect(curitiba.first.id, 'curitiba');
  });
}
