import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('auth email templates do not load remote assets', () {
    final files = Directory('supabase/templates')
        .listSync()
        .whereType<File>()
        .where((file) => file.path.endsWith('.html'))
        .toList();
    expect(files, hasLength(5));
    for (final file in files) {
      final html = file.readAsStringSync();
      final lowered = html.toLowerCase();
      expect(lowered, isNot(contains('<img')), reason: file.path);
      expect(lowered, isNot(contains('https://')), reason: file.path);
      expect(lowered, isNot(contains('http://')), reason: file.path);
      expect(
        html,
        contains('O link leva a nicolas00saliba.github.io/scapematch.'),
        reason: file.path,
      );
      expect(html, contains('ScapeMatch'), reason: file.path);
    }
  });
}
