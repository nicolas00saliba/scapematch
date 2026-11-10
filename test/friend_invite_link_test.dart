import 'package:flutter_test/flutter_test.dart';
import 'package:scapematch/core/mode/app_mode.dart';
import 'package:scapematch/core/sharing/public_origins.dart';
import 'package:scapematch/core/ui/app_keys.dart';
import 'package:scapematch/features/auth/data/fake_auth_repository.dart';
import 'package:scapematch/features/auth/presentation/login_screen.dart';
import 'package:scapematch/features/onboarding/data/onboarding_store.dart';
import 'package:scapematch/features/onboarding/presentation/onboarding_controller.dart';
import 'package:scapematch/features/onboarding/presentation/onboarding_screen.dart';
import 'package:scapematch/features/social/domain/social_rules.dart';
import 'package:scapematch/features/social/presentation/friend_invite_screen.dart';
import 'package:scapematch/providers/repositories.dart';

import 'support/pump_app.dart';

void main() {
  const code = 'abc123def456';

  test('the friend QR uses the real app host and the invite path', () {
    final link = SocialRules.inviteLink(code);
    final uri = Uri.parse(link);
    expect(link, '$playerAppOrigin/amigos/c/$code');
    expect(uri, Uri.parse('https://app.escapematch.com.br/amigos/c/$code'));
    expect(uri.hasQuery, isFalse);
    expect(uri.hasFragment, isFalse);
    expect(link.contains('scapematch.app'), isFalse);
  });

  testWidgets(
    'a friend-invite deep link skips the intro and returns after login',
    (tester) async {
      final uri = Uri.parse(SocialRules.inviteLink(code));
      final location = uri.hasQuery ? '${uri.path}?${uri.query}' : uri.path;
      tester.platformDispatcher.defaultRouteNameTestValue = location;
      addTearDown(tester.platformDispatcher.clearDefaultRouteNameTestValue);

      await pumpScapeMatch(
        tester,
        showOnboarding: true,
        onboardingMode: AppMode.real,
        overrides: [
          onboardingStoreProvider.overrideWithValue(
            OnboardingStore(seen: false),
          ),
          authRepositoryProvider.overrideWithValue(
            FakeAuthRepository(signedIn: null),
          ),
        ],
      );

      expect(find.byType(OnboardingScreen), findsNothing);
      expect(find.byType(FriendInviteScreen), findsOneWidget);
      expect(find.text('Código $code'), findsOneWidget);
      expect(find.text('Entrar para pedir amizade'), findsOneWidget);

      await tester.tap(find.text('Entrar para pedir amizade'));
      await tester.pumpAndSettle();
      expect(find.byType(LoginScreen), findsOneWidget);

      await tester.enterText(
        find.byKey(AppKeys.loginEmail),
        'nicolas@exemplo.invalid',
      );
      await tester.enterText(
        find.byKey(AppKeys.loginPassword),
        'senha-exemplo',
      );
      await tester.tap(find.byKey(AppKeys.loginSubmit));
      await tester.pumpAndSettle();

      expect(find.byType(LoginScreen), findsNothing);
      expect(find.byType(OnboardingScreen), findsNothing);
      expect(find.byType(FriendInviteScreen), findsOneWidget);
      expect(find.byKey(AppKeys.redeemInvite), findsOneWidget);
      expect(find.text('Código $code'), findsOneWidget);
    },
  );
}
