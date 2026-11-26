import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scapematch/features/cities/domain/city.dart';
import 'package:scapematch/features/cities/domain/city_search.dart';
import 'package:scapematch/features/cities/presentation/searchable_city_field.dart';

List<City> _many() => [
  for (var i = 0; i < 14; i += 1)
    City(
      id: 'cidade-$i',
      name: 'Cidade $i',
      stateCode: 'PR',
      stateName: 'Paraná',
    ),
  const City(
    id: 'sao-luis-do-quitunde-al',
    name: 'São Luís do Quitunde',
    stateCode: 'AL',
    stateName: 'Alagoas',
  ),
];

void main() {
  test('a busca da lista do jogador ignora acento e filtra por UF', () {
    final cities = _many();
    expect(searchCities(cities: cities, query: 'sao luis').map((c) => c.id), [
      'sao-luis-do-quitunde-al',
    ]);
    expect(searchCities(cities: cities, stateCode: 'AL').map((c) => c.id), [
      'sao-luis-do-quitunde-al',
    ]);
    expect(
      searchCities(cities: cities, query: 'cidade 1').first.id,
      'cidade-1',
    );
    expect(foldMunicipalityQuery("Olho d'Água"), 'olho dagua');
  });

  testWidgets('lista curta é dropdown; lista longa ganha estado e busca', (
    tester,
  ) async {
    String? picked;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SearchableCityFormField(
            cities: _many().take(5).toList(),
            cityId: null,
            onChanged: (value) => picked = value,
          ),
        ),
      ),
    );
    expect(find.byType(DropdownButtonFormField<String>), findsOneWidget);
    expect(find.byType(TextField), findsNothing);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SearchableCityFormField(
            cities: _many(),
            cityId: null,
            fieldKey: const Key('city'),
            onChanged: (value) => picked = value,
          ),
        ),
      ),
    );
    await tester.enterText(find.byKey(const Key('city')), 'sao luis');
    await tester.pumpAndSettle();
    await tester.tap(find.text('São Luís do Quitunde').last);
    await tester.pumpAndSettle();
    expect(picked, 'sao-luis-do-quitunde-al');
  });

  test('o app do jogador não importa o catálogo IBGE', () {
    final offenders = <String>[];
    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final text = entity.readAsStringSync();
      if (text.contains('brazilian_municipalities') ||
          text.contains('municipios_ibge')) {
        offenders.add(entity.path);
      }
    }
    expect(offenders, isEmpty);
    expect(
      File('pubspec.yaml').readAsStringSync().contains('municipios_ibge'),
      isFalse,
    );
  });
}
