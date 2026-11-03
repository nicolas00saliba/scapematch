import 'package:flutter/material.dart';
import 'package:scapematch/core/ui/window_class.dart';

/// No celular, centra a página numa coluna da largura do aparelho.
/// No site, a página usa a janela, com respiro nas laterais.
/// [desktopMaxWidth] limita formulários e textos longos.
class AppScaffold extends StatelessWidget {
  const AppScaffold({
    super.key,
    this.appBar,
    required this.body,
    this.bottomBar,
    this.desktopMaxWidth,
  });

  final PreferredSizeWidget? appBar;
  final Widget body;
  final Widget? bottomBar;

  /// Teto da coluna no celular.
  static const maxWidth = 560.0;

  /// Formulário curto, como entrar e criar conta.
  static const formMax = 560.0;

  /// Texto corrido: termos, notícia, aviso.
  static const readingMax = 760.0;

  /// Quando a página é um formulário ou um texto, limita a coluna no site.
  final double? desktopMaxWidth;

  static const desktopGutter = 32.0;

  @override
  Widget build(BuildContext context) {
    final desktop = isScapeDesktop(context);
    final cap = desktop ? desktopMaxWidth : maxWidth;
    return Scaffold(
      appBar: appBar,
      body: SafeArea(
        top: appBar == null,
        bottom: bottomBar == null,
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: cap ?? double.infinity),
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: desktop ? desktopGutter : 0,
              ),
              child: body,
            ),
          ),
        ),
      ),
      bottomNavigationBar: bottomBar == null
          ? null
          : Material(
              color: Theme.of(context).scaffoldBackgroundColor,
              child: SafeArea(
                // heightFactor keeps this bar as tall as the button.
                // A plain Center would grow to the whole screen and hide the page.
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    desktop ? desktopGutter : 20,
                    8,
                    desktop ? desktopGutter : 20,
                    12,
                  ),
                  child: Center(
                    heightFactor: 1,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: maxWidth),
                      child: bottomBar,
                    ),
                  ),
                ),
              ),
            ),
    );
  }
}
