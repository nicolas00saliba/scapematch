import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scapematch/features/payments/data/pagbank_connect_return.dart';
import 'package:scapematch/features/payments/presentation/pagbank_connect_return_page.dart';

void main() {
  test('só a rota do Connect lê code e state', () {
    final hit = PagbankConnectReturn.fromUri(
      Uri.parse(
        'https://parceiro.escapematch.com.br/pagbank/retorno?code=abc&state=def',
      ),
    );
    expect(hit?.code, 'abc');
    expect(hit?.state, 'def');
    expect(
      PagbankConnectReturn.fromUri(
        Uri.parse('https://parceiro.escapematch.com.br/?code=abc&state=def'),
      ),
      isNull,
    );
    expect(
      PagbankConnectReturn.fromUri(
        Uri.parse(
          'https://admin.escapematch.com.br/pagbank/retorno?code=&state=def',
        ),
      ),
      isNull,
    );
  });

  testWidgets('a página troca o code e o state uma vez', (tester) async {
    final seen = <PagbankConnectReturn>[];
    await tester.pumpWidget(
      MaterialApp(
        home: PagbankConnectReturnPage(
          hit: const PagbankConnectReturn(code: 'code-1', state: 'state-1'),
          complete: (hit) async {
            seen.add(hit);
            return true;
          },
          onDone: () {},
        ),
      ),
    );
    expect(find.text('Ligando a casa à PagBank.'), findsOneWidget);
    await tester.pump();
    expect(seen, hasLength(1));
    expect(seen.single.code, 'code-1');
    expect(seen.single.state, 'state-1');
    expect(find.text('A casa está ligada à PagBank.'), findsOneWidget);
  });
}
