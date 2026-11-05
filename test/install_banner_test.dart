import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scapematch/app/theme.dart';
import 'package:scapematch/core/pwa/install_offer.dart';
import 'package:scapematch/core/pwa/pwa_frame.dart';
import 'package:scapematch/core/ui/app_keys.dart';

void main() {
  test('o aviso some instalado, fechado ou fora do app real', () {
    expect(
      installOfferFor(
        enabled: true,
        standalone: false,
        dismissed: false,
        ios: false,
        promptReady: true,
      ),
      InstallOffer.prompt,
    );
    expect(
      installOfferFor(
        enabled: true,
        standalone: false,
        dismissed: false,
        ios: true,
        promptReady: false,
      ),
      InstallOffer.instructions,
    );
    expect(
      installOfferFor(
        enabled: true,
        standalone: false,
        dismissed: false,
        ios: true,
        promptReady: true,
      ),
      InstallOffer.prompt,
    );
    for (final blocked in [
      (enabled: false, standalone: false, dismissed: false),
      (enabled: true, standalone: true, dismissed: false),
      (enabled: true, standalone: false, dismissed: true),
    ]) {
      expect(
        installOfferFor(
          enabled: blocked.enabled,
          standalone: blocked.standalone,
          dismissed: blocked.dismissed,
          ios: true,
          promptReady: true,
        ),
        isNull,
      );
    }
    expect(
      installOfferFor(
        enabled: true,
        standalone: false,
        dismissed: false,
        ios: false,
        promptReady: false,
      ),
      isNull,
    );
  });

  testWidgets('o iPhone mostra Compartilhar e o fechar esconde', (
    tester,
  ) async {
    var closed = false;
    await tester.pumpWidget(
      _harness(
        InstallBanner(
          offer: InstallOffer.instructions,
          onDismiss: () => closed = true,
        ),
      ),
    );
    expect(find.text(InstallMessages.title), findsOneWidget);
    expect(find.text(InstallMessages.iosSteps), findsOneWidget);
    await tester.tap(find.byKey(AppKeys.installBannerDismiss));
    expect(closed, isTrue);
  });

  testWidgets('no Android o toque pede a instalação', (tester) async {
    var installs = 0;
    await tester.pumpWidget(
      _harness(
        InstallBanner(
          offer: InstallOffer.prompt,
          onDismiss: () {},
          onInstall: () async => installs++,
        ),
      ),
    );
    expect(find.text(InstallMessages.iosSteps), findsNothing);
    await tester.tap(find.byKey(AppKeys.installBannerAction));
    await tester.pump();
    expect(installs, 1);
  });
}

Widget _harness(Widget banner) {
  return MaterialApp(
    theme: buildAppTheme(Brightness.light),
    home: Scaffold(body: banner),
  );
}
