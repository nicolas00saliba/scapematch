import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:scapematch/core/data/sample_data.dart';
import 'package:scapematch/core/data/sample_ids.dart';
import 'package:scapematch/core/sharing/group_link.dart';
import 'package:scapematch/core/sharing/invite_message.dart';
import 'package:scapematch/core/time/clock.dart';
import 'package:scapematch/core/ui/app_keys.dart';
import 'package:scapematch/features/auth/data/fake_auth_repository.dart';
import 'package:scapematch/features/auth/presentation/login_screen.dart';
import 'package:scapematch/features/auth/presentation/signup_screen.dart';
import 'package:scapematch/features/groups/data/fake_group_repository.dart';
import 'package:scapematch/features/groups/domain/group_outcomes.dart';
import 'package:scapematch/features/groups/presentation/group_messages.dart';
import 'package:scapematch/features/groups/presentation/invite_screen.dart';
import 'package:scapematch/providers/repositories.dart';

import 'support/pump_app.dart';
import 'support/sample_clock.dart';

void main() {
  test('the invite message carries the room, the time and the link', () {
    final group = buildSampleDatabase(now: sampleNow).groups
        .firstWhere((group) => group.id == SampleIds.groupSpCoberturaOpen);
    final message = inviteMessage(group, onWeb: false);
    final link = groupLink(group.id, onWeb: false);
    expect(message, contains(group.roomName));
    expect(message, contains(group.cityName));
    expect(message, contains('vaga'));
    expect(message, contains(link));
    expect(link, '/convite/${group.id}');
    expect(whatsAppShareUrl(message), contains('https://wa.me/?text='));
    expect(whatsAppShareUrl('a b'), contains('a%20b'));

    final onGroup = Uri.parse(
      'https://nicolas00saliba.github.io/scapematch/groups/${group.id}',
    );
    expect(
      groupLink(group.id, onWeb: true, page: onGroup, baseHref: '/scapematch/'),
      'https://nicolas00saliba.github.io/scapematch/convite/${group.id}',
    );
    final local = Uri.parse('http://127.0.0.1:8766/groups/${group.id}');
    expect(
      groupLink(group.id, onWeb: true, page: local, baseHref: '/'),
      'http://127.0.0.1:8766/convite/${group.id}',
    );
  });

  testWidgets('a logged-out invite shows the group and signup joins it', (
    tester,
  ) async {
    final clock = FixedClock(sampleNow);
    final database = buildSampleDatabase(now: sampleNow);
    final groups = FakeGroupRepository(
      database,
      clock: clock,
      latency: Duration.zero,
    );
    await pumpScapeMatch(
      tester,
      overrides: [
        clockProvider.overrideWithValue(clock),
        fakeDatabaseProvider.overrideWithValue(database),
        groupRepositoryProvider.overrideWithValue(groups),
        authRepositoryProvider.overrideWithValue(
          FakeAuthRepository(signedIn: null),
        ),
      ],
    );
    await _openInvite(tester, SampleIds.groupSpCoberturaOpen);

    expect(find.byType(InviteScreen), findsOneWidget);
    expect(find.text('Cobertura da Paulista'), findsWidgets);
    expect(find.text('Quem vai'), findsOneWidget);
    expect(find.byKey(AppKeys.editGroup), findsNothing);
    expect(find.byKey(AppKeys.deleteGroup), findsNothing);
    expect(find.text('Participar'), findsOneWidget);

    await tester.tap(find.byKey(AppKeys.participate));
    await tester.pumpAndSettle();
    expect(find.byType(LoginScreen), findsOneWidget);

    await tester.tap(find.byKey(AppKeys.goToSignup));
    await tester.pumpAndSettle();
    expect(find.byType(SignupScreen), findsOneWidget);

    await tester.enterText(find.byKey(AppKeys.signupName), 'Ana');
    await tester.enterText(
      find.byKey(AppKeys.signupEmail),
      'ana@exemplo.invalid',
    );
    await tester.enterText(find.byKey(AppKeys.signupPassword), 'senha');
    await tester.tap(find.byKey(AppKeys.signupSubmit));
    await tester.pumpAndSettle();

    expect(find.text('Ana'), findsWidgets);
    expect(find.text(GroupMessages.joinedBanner), findsOneWidget);
    expect(
      ProviderScope.containerOf(tester.element(find.text('Ana')))
          .read(pendingInviteStoreProvider)
          .groupId,
      isNull,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('a signed-in person joins from the invite without login', (
    tester,
  ) async {
    await pumpScapeMatch(tester);
    await _openInvite(tester, SampleIds.groupSpCoberturaOpen);
    await tester.tap(find.byKey(AppKeys.participate));
    await tester.pumpAndSettle();
    expect(find.byType(LoginScreen), findsNothing);
    expect(find.text(GroupMessages.joinedBanner), findsOneWidget);
  });

  testWidgets('a group that fills before signup explains it', (tester) async {
    final clock = FixedClock(sampleNow);
    final database = buildSampleDatabase(now: sampleNow);
    final groups = FakeGroupRepository(
      database,
      clock: clock,
      latency: Duration.zero,
    );
    await pumpScapeMatch(
      tester,
      overrides: [
        clockProvider.overrideWithValue(clock),
        fakeDatabaseProvider.overrideWithValue(database),
        groupRepositoryProvider.overrideWithValue(groups),
        authRepositoryProvider.overrideWithValue(
          FakeAuthRepository(signedIn: null),
        ),
      ],
    );
    const id = SampleIds.groupCwbCofreAlmost;
    await _openInvite(tester, id);
    await tester.tap(find.byKey(AppKeys.participate));
    await tester.pumpAndSettle();

    var guard = 0;
    while (guard < 8) {
      final current = await groups.getById(id);
      if (current == null || current.isFull) {
        break;
      }
      final joined = await groups.join(
        id,
        participantUserId: 'fill-$guard',
        participantName: 'Pessoa $guard',
      );
      expect(joined, isA<JoinSuccess>());
      guard += 1;
    }
    expect((await groups.getById(id))!.isFull, isTrue);

    await tester.tap(find.byKey(AppKeys.goToSignup));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(AppKeys.signupName), 'Bia');
    await tester.enterText(
      find.byKey(AppKeys.signupEmail),
      'bia@exemplo.invalid',
    );
    await tester.enterText(find.byKey(AppKeys.signupPassword), 'senha');
    await tester.tap(find.byKey(AppKeys.signupSubmit));
    await tester.pumpAndSettle();

    expect(find.text(GroupMessages.inviteBecameFull), findsOneWidget);
    expect(find.text('O Cofre do Café'), findsWidgets);
    expect(
      ProviderScope.containerOf(
        tester.element(find.text(GroupMessages.inviteBecameFull)),
      ).read(pendingInviteStoreProvider).groupId,
      isNull,
    );
  });

  testWidgets('Convidar shows the message and copies the invite link', (
    tester,
  ) async {
    await pumpScapeMatch(tester);
    await _openInvite(tester, SampleIds.groupSpCoberturaOpen);
    // Já logado: entra e o detalhe tem Convidar.
    await tester.tap(find.byKey(AppKeys.participate));
    await tester.pumpAndSettle();

    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String?;
        }
        return null;
      },
    );
    addTearDown(() {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      );
    });

    await tester.tap(find.byKey(AppKeys.inviteGroup));
    await tester.pumpAndSettle();
    final message = tester.widget<SelectableText>(
      find.byKey(AppKeys.inviteMessage),
    );
    expect(message.data, contains('Cobertura da Paulista'));
    expect(
      message.data,
      contains('/convite/${SampleIds.groupSpCoberturaOpen}'),
    );
    expect(message.data, contains('vaga'));

    await tester.tap(find.byKey(AppKeys.shareGroup));
    await tester.pump();
    expect(copied, '/convite/${SampleIds.groupSpCoberturaOpen}');
  });

  testWidgets('a missing invite and a started group say so', (tester) async {
    final database = buildSampleDatabase(now: sampleNow);
    final group = database.groups.firstWhere(
      (item) => item.id == SampleIds.groupSpCoberturaOpen,
    );
    final clock = FixedClock(group.startsAt.add(const Duration(minutes: 1)));
    final groups = FakeGroupRepository(
      database,
      clock: clock,
      latency: Duration.zero,
    );
    await pumpScapeMatch(
      tester,
      overrides: [
        clockProvider.overrideWithValue(clock),
        fakeDatabaseProvider.overrideWithValue(database),
        groupRepositoryProvider.overrideWithValue(groups),
        authRepositoryProvider.overrideWithValue(
          FakeAuthRepository(signedIn: null),
        ),
      ],
    );
    await _openInvite(tester, 'grupo-que-nao-existe');
    expect(find.text('Convite não encontrado'), findsOneWidget);

    await _openInvite(tester, SampleIds.groupSpCoberturaOpen);
    expect(find.text('Este grupo já começou'), findsOneWidget);
    expect(find.text('Participar'), findsNothing);
  });

  testWidgets('invite and auth fit a phone and a wide window', (tester) async {
    for (final size in const [Size(390, 844), Size(1280, 800)]) {
      await pumpScapeMatch(
        tester,
        overrides: [
          authRepositoryProvider.overrideWithValue(
            FakeAuthRepository(signedIn: null),
          ),
        ],
      );
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      await tester.pumpAndSettle();
      await _openInvite(tester, SampleIds.groupSpCoberturaOpen);
      expect(tester.takeException(), isNull, reason: '$size invite');
      await tester.tap(find.byKey(AppKeys.participate));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: '$size login');
      await tester.tap(find.byKey(AppKeys.goToSignup));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: '$size signup');
    }
  });
}

Future<void> _openInvite(WidgetTester tester, String id) async {
  GoRouter.of(tester.element(find.byType(Scaffold).first)).go('/convite/$id');
  await tester.pumpAndSettle();
}
