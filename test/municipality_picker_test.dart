import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scapematch/features/cities/presentation/municipality_picker.dart';

void main() {
  testWidgets('escolhe a cidade pelo estado e pela busca sem acento', (
    tester,
  ) async {
    var cityId = 'curitiba';
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MunicipalityPicker(
            cityId: cityId,
            cityFieldKey: const Key('venue-city'),
            stateFieldKey: const Key('venue-state'),
            onChanged: (value) => cityId = value,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Curitiba'), findsOneWidget);
    expect(find.text('PR — Paraná'), findsOneWidget);

    await tester.tap(find.byKey(const Key('venue-city')));
    await tester.enterText(find.byKey(const Key('venue-city')), 'londrina');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Londrina').last);
    await tester.pumpAndSettle();
    expect(cityId, 'londrina-pr');

    await tester.enterText(
      find.byKey(const Key('venue-city')),
      'florianopolis',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Florianópolis').last);
    await tester.pumpAndSettle();
    expect(cityId, 'florianopolis-sc');
  });
}
