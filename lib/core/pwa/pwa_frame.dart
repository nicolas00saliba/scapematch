import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:scapematch/core/mode/app_mode.dart';
import 'package:scapematch/core/pwa/css_safe_insets.dart';
import 'package:scapematch/core/pwa/install_bridge.dart';
import 'package:scapematch/core/pwa/install_offer.dart';
import 'package:scapematch/core/ui/app_keys.dart';
import 'package:scapematch/core/ui/window_class.dart';

/// O release real na web pede instalação. Testes e a demonstração não.
bool get installBannerEnabled =>
    kIsWeb && kReleaseMode && kAppMode == AppMode.real;

abstract final class InstallMessages {
  static const title = 'Instalar o app';
  static const iosSteps = 'Compartilhar > Adicionar à Tela de Início';
  static const dismiss = 'Fechar';
}

/// Empurra o conteúdo para fora do notch quando o Flutter ainda não lê
/// a safe area. Se o motor já reportar o recuo, não soma de novo.
class WebSafeInsets extends StatefulWidget {
  const WebSafeInsets({super.key, required this.child});

  final Widget child;

  @override
  State<WebSafeInsets> createState() => _WebSafeInsetsState();
}

class _WebSafeInsetsState extends State<WebSafeInsets>
    with WidgetsBindingObserver {
  EdgeInsets _css = EdgeInsets.zero;

  @override
  void initState() {
    super.initState();
    if (!kIsWeb) return;
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _measure());
    // O motor troca o viewport meta depois do primeiro frame.
    Future<void>.delayed(const Duration(milliseconds: 400), _measure);
  }

  @override
  void dispose() {
    if (kIsWeb) WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeMetrics() => _measure();

  void _measure() {
    if (!mounted || !kIsWeb) return;
    final next = readCssSafeAreaInsets();
    if (next == _css) return;
    setState(() => _css = next);
  }

  @override
  Widget build(BuildContext context) {
    if (!kIsWeb || _css == EdgeInsets.zero) return widget.child;
    final media = MediaQuery.of(context);
    final extra = EdgeInsets.fromLTRB(
      math.max(0, _css.left - media.viewPadding.left),
      math.max(0, _css.top - media.viewPadding.top),
      math.max(0, _css.right - media.viewPadding.right),
      math.max(0, _css.bottom - media.viewPadding.bottom),
    );
    if (extra == EdgeInsets.zero) return widget.child;
    final viewPadding = EdgeInsets.fromLTRB(
      media.viewPadding.left + extra.left,
      media.viewPadding.top + extra.top,
      media.viewPadding.right + extra.right,
      media.viewPadding.bottom + extra.bottom,
    );
    final padding = EdgeInsets.fromLTRB(
      math.max(0, viewPadding.left - media.viewInsets.left),
      math.max(0, viewPadding.top - media.viewInsets.top),
      math.max(0, viewPadding.right - media.viewInsets.right),
      math.max(0, viewPadding.bottom - media.viewInsets.bottom),
    );
    return MediaQuery(
      data: media.copyWith(padding: padding, viewPadding: viewPadding),
      child: widget.child,
    );
  }
}

/// Aviso discreto no celular. No site largo não aparece.
class InstallBannerHost extends StatefulWidget {
  const InstallBannerHost({super.key, required this.child});

  final Widget child;

  @override
  State<InstallBannerHost> createState() => _InstallBannerHostState();
}

class _InstallBannerHostState extends State<InstallBannerHost> {
  InstallOffer? _offer;

  @override
  void initState() {
    super.initState();
    if (!installBannerEnabled) return;
    listenForInstallPrompt(_sync);
    WidgetsBinding.instance.addPostFrameCallback((_) => _sync());
  }

  void _sync() {
    if (!mounted || !installBannerEnabled) return;
    final signals = readInstallSignals();
    final next = installOfferFor(
      enabled: true,
      standalone: signals.standalone,
      dismissed: signals.dismissed,
      ios: signals.ios,
      promptReady: signals.promptReady,
    );
    if (next == _offer) return;
    setState(() => _offer = next);
  }

  Future<void> _install() async {
    final outcome = await launchBrowserInstall();
    if (outcome == 'accepted') rememberInstallDismissed();
    _sync();
  }

  void _dismiss() {
    rememberInstallDismissed();
    _sync();
  }

  @override
  Widget build(BuildContext context) {
    final offer = _offer;
    if (offer == null || isScapeDesktop(context)) return widget.child;
    return Column(
      children: [
        InstallBanner(offer: offer, onInstall: _install, onDismiss: _dismiss),
        Expanded(
          child: MediaQuery.removePadding(
            context: context,
            removeTop: true,
            child: widget.child,
          ),
        ),
      ],
    );
  }
}

class InstallBanner extends StatelessWidget {
  const InstallBanner({
    super.key,
    required this.offer,
    required this.onDismiss,
    this.onInstall,
  });

  final InstallOffer offer;
  final VoidCallback onDismiss;
  final Future<void> Function()? onInstall;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final steps = offer == InstallOffer.instructions;
    return ColoredBox(
      color: theme.scaffoldBackgroundColor,
      child: SafeArea(
        bottom: false,
        left: false,
        right: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
          child: Material(
            key: AppKeys.installBanner,
            color: scheme.surface,
            elevation: 1,
            shadowColor: const Color(0x140E1716),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(color: scheme.outlineVariant),
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 4, 4),
              child: Row(
                children: [
                  Icon(
                    Icons.install_mobile_outlined,
                    size: 20,
                    color: scheme.primary,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: steps
                        ? Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                InstallMessages.title,
                                style: theme.textTheme.titleSmall?.copyWith(
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              Text(
                                InstallMessages.iosSteps,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: scheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          )
                        : Align(
                            alignment: Alignment.centerLeft,
                            child: TextButton(
                              key: AppKeys.installBannerAction,
                              onPressed: onInstall,
                              style: TextButton.styleFrom(
                                foregroundColor: scheme.primary,
                                visualDensity: VisualDensity.compact,
                                textStyle: theme.textTheme.titleSmall
                                    ?.copyWith(fontWeight: FontWeight.w800),
                              ),
                              child: const Text(InstallMessages.title),
                            ),
                          ),
                  ),
                  IconButton(
                    key: AppKeys.installBannerDismiss,
                    tooltip: InstallMessages.dismiss,
                    onPressed: onDismiss,
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.close, size: 18),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Safe area da web e o aviso de instalar, em volta do app.
class PwaFrame extends StatelessWidget {
  const PwaFrame({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return WebSafeInsets(
      child: InstallBannerHost(child: child),
    );
  }
}
