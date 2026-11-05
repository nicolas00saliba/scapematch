import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:scapematch/features/auth/data/password_strength.dart';

void main() {
  test('local rule asks for 8 characters with letters and digits', () async {
    var calls = 0;
    final client = MockClient((request) async {
      calls += 1;
      return http.Response('', 200);
    });

    expect(
      await rejectPassword('curta1', httpClient: client),
      passwordRuleMessage,
    );
    expect(
      await rejectPassword('abcdefgh', httpClient: client),
      passwordRuleMessage,
    );
    expect(
      await rejectPassword('12345678', httpClient: client),
      passwordRuleMessage,
    );
    expect(calls, 0);
  });

  test('sends only the hash prefix and rejects a leaked password', () async {
    const password = 'sala1234';
    final hash = sha1.convert(utf8.encode(password)).toString().toUpperCase();
    late http.Request seen;
    final client = MockClient((request) async {
      seen = request;
      return http.Response(
        '${hash.substring(5)}:12\n0018A45C4D1DEF81644B54AB7F969B88D65:0\n',
        200,
      );
    });

    expect(
      await rejectPassword(password, httpClient: client),
      leakedPasswordMessage,
    );
    expect(
      seen.url.toString(),
      'https://api.pwnedpasswords.com/range/${hash.substring(0, 5)}',
    );
    expect(seen.url.toString(), isNot(contains(password)));
    expect(seen.headers['add-padding'], 'true');
    expect(seen.url.path, endsWith(hash.substring(0, 5)));
    expect(seen.url.path, isNot(contains(hash.substring(5))));
  });

  test('padding with count zero does not reject the password', () async {
    const password = 'sala1234';
    final hash = sha1.convert(utf8.encode(password)).toString().toUpperCase();
    final client = MockClient((request) async {
      return http.Response('${hash.substring(5)}:0\nABCDEF:4\n', 200);
    });

    expect(await rejectPassword(password, httpClient: client), isNull);
  });

  test('a clean password is accepted', () async {
    final client = MockClient((request) async {
      return http.Response('ABCDEF0123456789ABCDEF0123456789ABC:2\n', 200);
    });

    expect(await rejectPassword('sala1234', httpClient: client), isNull);
  });

  test('api failure does not block the password', () async {
    final down = MockClient((request) async => http.Response('nope', 503));
    final offline = MockClient((request) async {
      throw Exception('sem rede');
    });

    expect(await rejectPassword('sala1234', httpClient: down), isNull);
    expect(await rejectPassword('sala1234', httpClient: offline), isNull);
  });
}
