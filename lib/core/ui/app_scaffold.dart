import 'package:flutter/material.dart';

/// Centers the page on a phone-width column so the web layout stays calm.
class AppScaffold extends StatelessWidget {
  const AppScaffold({
    super.key,
    this.appBar,
    required this.body,
    this.bottomBar,
  });

  final PreferredSizeWidget? appBar;
  final Widget body;
  final Widget? bottomBar;

  static const maxWidth = 560.0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: appBar,
      body: SafeArea(
        top: appBar == null,
        bottom: bottomBar == null,
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: maxWidth),
            child: body,
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
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
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
